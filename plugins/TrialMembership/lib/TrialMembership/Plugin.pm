package TrialMembership::Plugin;

use strict;
use warnings;

use base qw(MT::Plugin);
use MT::Util qw( ts2epoch encode_url );

sub save_timers {
    # This function is responsible for both loading and saving data.
    my $app    = MT->instance;
    my $plugin = MT->component('TrialMembership');
    my $param  = {};

    # Grab any set timers and roles, and save them to the @data array so 
    # that they're easy to work with later.
    my @data;
    my $counter = 1;
    while ( $app->param("role_$counter") ) {
        if ( $app->param("role_$counter") ) {
            push @data, {
                role_id       => $app->param("role_$counter"),
                timer         => $app->param("timer_$counter") || '30',
                allow_renewal => $app->param("allow_renewal_$counter") || '0',
                email_renewal => $app->param("email_renewal_$counter") || '0',
            };
        }
        $counter++;
    }

    # If any roles & timers were found, save them.
    if (scalar @data) {
        # We need to use a special PluginData area to save the timers.
        # Trying to save them with TrialMembership results in them
        # being overwritten when the plugin Settings are saved. Saving
        # with separate PluginData will work around that.
        use MT::PluginData;
        my $plugindata = MT::PluginData->load({
            plugin => 'TrialMembership',
            key    => 'timers',
        });
        if ( !$plugindata ) {
            $plugindata = MT::PluginData->new;
            $plugindata->plugin('TrialMembership');
            $plugindata->key('timers');
        }

        $plugindata->data( \@data );
        $plugindata->save or die $plugindata->errstr;
        
        # Provide feedback to the user that the save was successful.
        $param->{saved} = 1;
    }

    # Now, build the interface page. Load timers & roles, too.

    # Load all of the roles available. These create the drop-down of
    # selection options for the user to choose from.
    my @system_roles = MT->model('role')->load(
        undef,
        { sort => 'name', }
    );
    my @roles;
    foreach my $role (@system_roles) {
        push @roles, {
            role_name => $role->name,
            # Even though this is the role ID, don't name the var
            # role_id, because role_id is the saved name used above.
            role      => $role->id
        }
    }
    $param->{roles} = \@roles;

    # Load any saved timers and roles that may have been saved.
    my $plugindata = MT::PluginData->load({ 
        plugin => 'TrialMembership',
        key    => 'timers' 
    });
    if ($plugindata) {
        my $timers = $plugindata->data;
        if ($timers) {
            $param->{selectors} = $timers;
        }
    }

    my $tmpl = $plugin->load_tmpl('settings.mtml');
    return $app->build_page( $tmpl, $param );
}

sub update_user_timers {
    # Run the task to disable users based on the saved settings.
    MT::Util::start_background_task(
        sub {
            # Load any saved timers and roles that may have been saved.
            my $plugindata = MT::PluginData->load({ 
                plugin => 'TrialMembership',
                key    => 'timers' 
            });
            my $timers = $plugindata->data;

            # Look at each timer that may have been set, then load the 
            # specified role ID on the mt_association table. That will
            # tell us which authors have that role applied. Then, look
            # at those authors to determine if they should be disabled.
            foreach my $timer (@$timers) {
                my $role_id = $timer->{role_id};
                # The timer is a "days" value. Multiply by 60 seconds
                # then by 60 minutes then by 24 hours to get the number
                # of seconds.
                my $expire = $timer->{timer} * 60 * 60 * 24;

                my @associations = MT->model('association')->load({ 
                    role_id => $role_id,
                });
                foreach my $assoc (@associations) {
                    my $author = MT->model('author')->load({
                        id     => $assoc->author_id,
                        status => MT::Author::ACTIVE(),
                    });
                    if ($author) {
                        # Use the last_activated meta column to determine
                        # if the user should expire, If the last_activated
                        # column hasn't been set yet, fall back to the
                        # created_on field. Use that date and the current
                        # date/time. If more than the specified time has
                        # elapsed, disable the user.
                        my $last = $author->last_activated 
                            || $author->created_on;
                        my $saved_time = ts2epoch(undef, $last);
                        my $cur_time   = time;

                        # Find the difference between the current time
                        # and the saved time; this tells us how many days
                        # have passed since the last activation.
                        my $elapsed_time = $cur_time - $saved_time;

                        # Then compare to the timer to decide if the 
                        # user should be disabled. If more time has elapsed
                        # than the timer allows for, disable the user.
                        if ($elapsed_time > $expire) {
                            # Change the user's status to pending, and put 
                            # a notification in the activity log.
                            _mark_user_pending($role_id, $timer, $author);
                        }
                    }
                }
            }
        }
    );
}

sub _mark_user_pending {
    # A user has met the rules of the timer, so their status is being changed.
    my $role_id  = shift;
    my ($timer, $author) = @_;

    # Is this user a "superuser"? We don't ever want to disable a
    # superuser! Also, check that the author is ACTIVE. No point in
    # changing the status of a user who isn't enabled.
    if ( !$author->is_superuser() 
        && ( $author->status == MT::Author::ACTIVE() )
      ) 
    {
        # If users should have the opportunity to renew access themselves,
        # we need to set their status to PENDING. If they should *not* be 
        # able to renew themselves, then their status should be set to
        # INACTIVE.
        if ($timer->{allow_renewal}) {
            $author->status( MT::Author::PENDING() );
            # Should the user be emailed when their access changes?
            if ($timer->{email_renewal}) {
                my $plugin = MT->component('TrialMembership');
                _email_user_for_renewal(
                    $plugin->get_config_value('user_email_subject', 'system'), 
                    $plugin->get_config_value('user_email_body', 'system'), 
                    $author
                );
            }
        }
        else {
            $author->status( MT::Author::INACTIVE() );
        }
        $author->save;

        # Save a note to the Activity log, and notify the admin.
        my $message = $plugin->name . ' disabled the user "' . $author->name 
            . '," who has the role "' . MT->model('role')->load($role_id)->name
            . '" assigned to them.';
        _admin_notification($message);
    }
}

sub _admin_notification {
    # Place notification in the Activity Log and send an email to the
    # administrator to notify them of the user change. We can reuse the
    # message for both the Activity Log and email body.
    my ($message) = @_;

    MT->log({ 
        message => $message,
        class   => "system",
        level   => MT::Log::INFO()
    });

    # Send a notification email to an administrator (if an address was 
    # provided) to let them know that this user is disabled.
    my $plugin = MT->component('TrialMembership');
    my $email = $plugin->get_config_value('email_address', 'system');
    if ($email) {
        require MT::Mail;
        my %head = ( 
            To      => $email, 
            Subject => "[" . $plugin->name . "] A user's status has changed."
        );
        MT::Mail->send(\%head, $message)
            or die MT::Mail->errstr;
    }
}

sub _email_user_for_renewal {
    # The current Trial Membership rule dictates that we email the disabled
    # user when their access is revoked. Send an email about this.
    my ($subject, $body, $author) = @_;
    
    if ( $author->email && $author->status == MT::Author::PENDING() ) {

        my $app = MT->instance;

        # Users must reset their password to enable access to their account
        # again.
        # Generate Token
        require MT::Util::Captcha;
        my $salt = MT::Util::Captcha->_generate_code(8);
        
        # The password reset expiration timer doesn't matter for our use, but
        # it's required. By default it's set to 1 hour in the future, which is
        # too short. We don't know when the user is disabled--it could be in 
        # the middle of the night or some other inconvenient time. When they
        # do get this email and go to reset the password, the expiration time
        # has passed and they're told to click to reactivate... again. It's
        # counterintuitive. So, lets set a much longer expiration time and
        # avoid the whole problem: set the expiration for 30 days.
        my $expires = time + ( 60 * 60 * 30 );

        my $token = MT::Util::perl_sha1_digest_hex(
            $salt . $expires . $app->config->SecretToken 
        );

        $author->password_reset($salt);
        $author->password_reset_expires($expires);
        #$author->password_reset_return_to($app->param('return_to'))
        #    if $app->param('return_to');
        $author->save;
        
        # Build a context that we can use for the subject and body.
        require MT::Template::Context;
        my $ctx = MT::Template::Context->new;
        $ctx->{__stash}{author} = $author;

        # Create the password reset URL. For some reason $app isn't 
        # "complete" and I can't just do $app->base. So, just cheat and use 
        # this TrialMembershipURL config directive.
        my $url = $app->config->TrialMembershipURL
            . "?__mode=new_pw&token=$token&email=" 
            . encode_url($author->email);

        $ctx->stash('reset_pw_url', $url);

        # Build the subject from the "template" that was entered in Trial
        # Membership settings.
        my $tmpl = MT->model('template')->new();
        $tmpl->text( $subject );
        $subject = $tmpl->build($ctx) or die $tmpl->errstr;

        # Build the body from the "template" that was entered in Trial
        # Membership settings.
        $tmpl = MT->model('template')->new();
        $tmpl->text( $body );
        $body = $tmpl->build($ctx) or die $tmpl->errstr;

        # Send the email!
        require MT::Mail;
        my %head = ( 
            To      => $author->email, 
            Subject => $subject,
        );
        
        MT::Mail->send(\%head, $body)
            or die MT::Mail->errstr;
    }
}

sub post_save_author {
    # Increment a counter whenever a user is made active.
    my ($cb, $app, $obj, $original) = @_;
    
    # Compare the original and new data. If the original status was *not*
    # ACTIVE (we want to track them whether they were DISABLED *or* 
    # PENDING), and if their current status is ACTIVE, that means their
    # status changed. Count it.
    if ( $original->status ne MT::Author::ACTIVE()
        && $obj->status eq MT::Author::ACTIVE() 
      ) 
    {
        # Track activations: count (if necessary)
        _track_activations($obj);
    }

    # Return 1 so that everything stays copacetic.
    1;
}

sub _track_activations {
    my ($author) = @_;
    # Check if a custom field has been selected to be used to track the 
    # number of activations. If no field has been selected, give up.
    my $plugin = MT->component('TrialMembership');
    my $selected_field = $plugin->get_config_value('track_activations', 'system');
    if ($selected_field) {
        # Create the custom field basename. Custom fields are prepended
        # with "field." so that's why we need this.
        my $basename = 'field.' . $selected_field;
        my $val = $author->$basename;

        # Increment the counter. For whatever reason we can't set the value
        # and save it at the same time, so just set it now.
        $val++;

        # Set the value--this is the number of times the account has
        # been activated.
        $author->$basename( $val );
    }
    
    # We also need to save *when* this account was re-activated. Save
    # the current date/time.
    my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
    $year += 1900;
    $mon  += 1;
    my $stamp = "$year-$mon-$mday $hour:$min:$sec";
    $author->last_activated( $stamp );

    # Lastly, of course, save any changes.
    $author->save;
}

1;

__END__
