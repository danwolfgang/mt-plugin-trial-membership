package TrialMembership::Tags;

use strict;
use warnings;

sub reset_pw_url {
    my ($ctx, $args) = @_;
    my $a = $ctx->stash('reset_pw_url');
    if (!defined $a) {
        return $ctx->error('The ResetPasswordURL tag must be used within the Trial Membership email body template.');
    }
    return $a;
}

1;

__END__
