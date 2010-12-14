package TrialMembership::Init;

use Sub::Install;

sub init_app {
    my ( $cb, $app ) = @_;
    return
      unless $app->isa('MT::App')
          && ( $app->can('query') || $app->can('param') );

    # TODO - This should not have to reinstall a subroutine. It should invoke
    #        a callback.
    Sub::Install::reinstall_sub({ 
        code => \&_new_password, 
        into => 'MT::CMS::Tools', 
        as => 'new_password', 
    });
}

# This routine is copied from MT::CMS::Tools::new_password, from MT 4.261.
# A few changes were made here: specifically we need to re-activate the user
# and increment the counter if the user is successfully re-activated.
sub _new_password {
    my $app = shift;
    my ($param) = @_;
    $param ||= {};

    my $token = $app->param('token');
    if ( !$token ) {
        return $app->start_recover(
            { error => $app->translate('Password reset token not found'), } );
    }

    my $email = $app->param('email');
    if ( !$email ) {
        return $app->start_recover(
            { error => $app->translate('Email address not found'), } );
    }

    my $class = $app->model('author');
    my @users = $class->load( { email => $email } );
    if ( !@users ) {
        return $app->start_recover(
            { error => $app->translate('User not found'), } );
    }

    # comparing token
    require MT::Util::Captcha;
    my $user;
    for my $u (@users) {
        my $salt    = $u->password_reset;
        my $expires = $u->password_reset_expires;
        my $compare = MT::Util::perl_sha1_digest_hex(
            $salt . $expires . $app->config->SecretToken );
        if ( $compare eq $token ) {
            if ( time > $u->password_reset_expires ) {
                return $app->start_recover(
                    {   error => $app->translate(
                            'Your request to change your password has expired.'
                        ),
                    }
                );
            }
            $user  = $u;
            last;
        }
    }

    if ( !$user ) {
        return $app->start_recover(
            { error => $app->translate('Invalid password reset request'), } );
    }

    # Password reset
    my $new_password = $app->param('password');
    if ($new_password) {
        my $again = $app->param('password_again');
        if ( !$again ) {
            $param->{'error'}
                = $app->translate('Please confirm your new password');
        }
        elsif ( $new_password ne $again ) {
            $param->{'error'} = $app->translate('Passwords do not match');
        }
        else {
            # If the user is coming from a Trial Membership renewal email
            # URL, then password_reset_return_to is *not* set. However, the
            # renewal email URL may have included a return_to parameter that
            # we can use.
            my $redirect = $user->password_reset_return_to 
                || $app->param('return_to')
                || '';

            $user->set_password($new_password);
            $user->password_reset(undef);
            $user->password_reset_expires(undef);
            $user->password_reset_return_to(undef);
            $user->save;
            $app->param( 'username', $user->name )
                if $user->type == MT::Author::AUTHOR();
                
            # Re-enable the user. Note that we only re-enable PENDING
            # users. We never want to enable a disabled (INACTIVE) user,
            # and there is no point in enabling an ACTIVE user.
            # Also, since we're re-enabling the user, we should update the
            # activations counter, if used.
            if ( $user->status eq MT::Author::PENDING() ) {
                $user->status( MT::Author::ACTIVE() );
                
                use TrialMembership::Plugin;
                TrialMembership::Plugin::_track_activations($user);
                
                # Save a note to the Activity log, and notify the admin.
                my $message = 'The user ' . $user->name 
                    . ' has activated their account.';
                TrialMembership::Plugin::_admin_notification($message);
            }

            if (ref $app eq 'MT::App::CMS' && !$redirect) {
                $app->login;
                return $app->return_to_dashboard( redirect => 1 );
            } else {
                if (!$redirect) {
                    my $cfg = $app->config;
                    $redirect = $cfg->ReturnToURL || '';
                }
                $app->make_commenter_session($user);
                if ($redirect) {
                    return $app->redirect($redirect);
                } else {
                    return $app->redirect_to_edit_profile();
                }
            }
        }
    }

    $param->{'email'}          = $email;
    $param->{'token'}          = $token;
    $param->{'password'}       = $app->param('password');
    $param->{'password_again'} = $app->param('password_again');
    $param->{'return_to'}      = $app->param('return_to');
    $app->add_breadcrumb( $app->translate('Password Recovery') );

    my $blog_id = $app->param('blog_id');
    $param->{'blog_id'}        = $blog_id if $blog_id;
    my $tmpl = $app->load_global_tmpl( { identifier => 'new_password',
            $blog_id ? ( blog_id => $app->param('blog_id') ) : () } );
    if (!$tmpl) {
        $tmpl = $app->load_tmpl( 'cms/dialog/new_password.tmpl' );
    }
    $tmpl->param($param);
    return $tmpl;
}

1;

__END__
