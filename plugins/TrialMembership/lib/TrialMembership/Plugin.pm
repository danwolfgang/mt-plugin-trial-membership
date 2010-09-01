package TrialMembership::Plugin;

use strict;
use warnings;

use base qw(MT::Plugin);
use MT::Util qw( ts2epoch );

sub save_timers {
    # This function is responsible for both loading and saving data.
    my $app    = MT->instance;
    my $plugin = MT->component('TrialMembership');
    
    # Grab any set timers and roles, then save them to the plugin config
    my @timers    = $app->param('timer');
    my @role_ids  = $app->param('role');
    my $count     = scalar @timers;

    my @data;
    for (my $i = 0; $i < $count; $i++) {
        if ( $role_ids[$i] && $timers[$i] ) {
            push @data, {
                role_id => $role_ids[$i],
                timer   => $timers[$i],
            };
        }
    }
    # If any roles & timers were found, save them.
    if (scalar @data) {
        $plugin->set_config_value('timers', \@data);
        # Save any previously-set email address, too. Saving it here, inside
        # of the timers "if" statement, works to trap if the user left this
        # field blank.
        $plugin->set_config_value('email', $app->param('email'));
    }

    # Now, build the interface page. Load timers & roles, too.
    my $param = {};
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
    my $timers = $plugin->get_config_value('timers', 'system');
    if ($timers) {
        $param->{selectors} = $timers;
    }
    else {
        # We need to create at least one element so that a single field
        # exists for the blank "add new" item.
        $param->{selectors} = { role_id => '', timer => '', };
    }
    
    $param->{email} = $plugin->get_config_value('email', 'system');

    my $tmpl = $plugin->load_tmpl('settings.mtml');
    return $app->build_page( $tmpl, $param );
}

sub update_user_timers {
    # Run the task to disable users based on the saved settings.
    MT::Util::start_background_task(
        sub {
            my $app    = MT->instance;
            my $plugin = MT->component('TrialMembership');
            my $timers = $plugin->get_config_value('timers', 'system');

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
                        # If the timer field hasn't been set, compare the
                        # author created_on field and the current date/time. If
                        # more than the specified time has elapsed, disable
                        # the user. Lastly, set the timer with the current
                        # timestamp.
                        my $saved_time = ts2epoch(undef, $author->created_on);
                        my $cur_time   = time;
                        # Find the difference between the current time
                        # and the saved time...
                        my $elapsed_time = $cur_time - $saved_time;
                        # Then compare to the timer to decide if the 
                        # user should be disabled.
                        if ($elapsed_time > $expire) {
                            # Disable the user, and put a notification
                            # in the activity log.
                            _disable_user($role_id, $author);
                        }
                    }
                }
            }
        }
    );
}

sub _disable_user {
    # We want to update the MT Activity Log
    my $role_id  = shift;
    my ($author) = @_;

    # Is this user a "superuser"? We don't ever want to disable
    # a superuser!
    if ( !$author->is_superuser() ) {
        # Set the author status to disabled and save.
        $author->status( MT::Author::INACTIVE() );
        $author->save;
    }

    # Place notification in the Activity Log and send an email.
    my $plugin = MT->component('TrialMembership');
    my $email = $plugin->get_config_value('email', 'system');
    # We can reuse the message for both the Activity Log and email body.
    my $message = $plugin->name . ' disabled the user "' . $author->name 
        . '," who has the role "' . MT->model('role')->load($role_id)->name
        . '" assigned to them.';

    MT->log({ 
        message => $message,
        class   => "system",
        level   => MT::Log::INFO()
    });
    # Only send a notification if an email address was saved.
    if ($email) {
        require MT::Mail;
        my %head = ( 
            To      => $email, 
            Subject => '[' . $plugin->name . '] A user has been disabled.'
        );
        MT::Mail->send(\%head, $message)
            or die MT::Mail->errstr;
    }
}

1;

__END__
