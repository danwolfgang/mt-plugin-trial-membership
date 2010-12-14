# Trial Membership Overview

The Trial Membership plugin for Movable Type and Melody can be used to disable users after a specified amount of time has elapsed. In other words, Commenters or Contributors (for example) can be allowed to participate and interact with your site for only a specified amount of time -- a trial membership.

Create a "rule" by selecting a Role and specifying a number of days to elapse. A user's status will be changed to Pending or Disabled after that specified time has elapsed and if they belong to the specified role. Users can "renew" access by changing their password, and be automatically notified when their status has changed.

Many "rules" can be created to target different groups of users. Stay abreast of which users have been disabled with an administrator email notification.


# Prerequisites

* Movable Type Pro 4.x


# Installation

This plugin is installed [just like any other Movable Type Plugin](http://www.majordojo.com/2008/12/the-ultimate-guide-to-installing-movable-type-plugins.php).

Be sure that `run-periodic-tasks` has been set up properly; this is used to run the rules you define.


# Using Trial Membership

This plugin add a single Page Action to the "Users: System-wide" screen, labeled Trial Membership. Select it to work with roles and timers.

To create a timer rule, select a role and specify a number of days. Any user who has the selected role applied to them, and for which the specified number of days have passed since the user was created (or since their last activation), will have their status changed.

An active user's status can be changed to either Disabled or Pending. Disabled users are completely locked-out of Movable Type; only an administrator can change their access. A Pending status forces the user to change their password to interact with the site again. (Note that system administrators can not be disabled by Trial Membership.)

Trial Membership will set users to status disabled by default. To set users to status pending, check the option "Allow the user to renew their access (set to status 'pending')."

Additionally, users can be notified when their status changes (that is, when their trial membership has expired); check the option "Notify the user when their access has expired." You'll likely want to customize the email sent to users -- see the next sections for details.

Use the "add another rule" link to create more rules. Use the "delete this rule" link to remove a rule.

The rules you define are used with Movable Type's Tasks framework. Be sure you have `run-periodic-tasks` set up to cause tasks to run on schedule.

## Plugin Configuration

Trial Membership has several options to configure at the System level plugin Settings screen.

The **Administrator Notification Email** field is pretty straight-forward. A notification email will be sent when a user's status is changed, meaning when they are disabled, and when they renew access. Note that even if this field is left blank, the Activity Log is updated with Trial Membership activity.

If you want to notify users when they are disabled you likely want to customize the email sent to them. Use the **User Email Subject** and **User Email Body** fields to craft the email. Template tags can be used in these fields. Enter plain-text in these fields (HTML email is not supported).

Use the **Track Activations** field to monitor the number of times a user renews their access. From this field you can select a custom field where the activation count can be saved. (Which means, yes, you need to create a custom field to use this feature. The "single-line text" or "multi-line text" custom fields are the only type of field that make sense to use here.)

Within your `mt-config.cgi`, set a config directive:

    TrialMembershipURL http://domain.com/path/to/mt-cp.cgi

The requirement of this config directive will (hopefully) be removed in a future release.

## Building a User Renewal Email

The user renewal email is in the author context, so author tags can be used right there. For example, create a list of all blogs this author has a role in:

    <mt:AuthorDisplayName setvar="author_name">Blogs by <mt:Var name="author_name">:
    <mt:Blogs><mt:Authors><mt:if tag="AuthorDisplayName" eq="$author_name">* <mt:BlogName>: <mt:BlogURL></mt:if></mt:Authors>
    </mt:Blogs>

Note that because this is a plain-text email extra spaces and new lines will show up. I have spaced the above code to make the final email look good.

Within the User Email Body field you will want to use the `ResetPasswordURL` tag. This tag builds a link to the "reset password" dialog, complete with the magic token. If you simply use this tag in your email, you will see that after the user has successfully changed their password they are redirected to their Edit Profile screen. There are a few ways to redirect them to a more useful page:

* Use the `ReturnToURL` configuration directive. More information at http://www.movabletype.org/documentation/appendices/config-directives/returntourl.html
* Append a `return_to` parameter to the `ResetPasswordURL` tag. This method requires some additional setup, but has flexibility because you can use MT tags to craft a unique return URL for each disabled user--such as by redirecting them to a blog they have permission to comment on.

### Using the `return_to` Parameter

Within the email body, specify the `return_to` parameter as follows:

    <mt:ResetPasswordURL>&return_to=http%3A%2F%2Featdrinksleepmovabletype.com

You can see I've set it to redirect to eatdrinksleepmovabletype.com. Note, however, that I've also encoded the URL.

Tags can also be used to create the `return_to` URL. The following example is spaced for readability. The `return_to` variable is being set to the URL of a blog that the author has permission to participate in. Note also that the `encode_url` modifier is used to encode the URL.

    <mt:AuthorDisplayName setvar="author_name">
    <mt:Blogs>
        <mt:Authors>
            <mt:If tag="AuthorDisplayName" eq="$author_name">
                <mt:BlogURL encode_url="1" setvar="return_to">
            </mt:If>
        </mt:Authors>
    </mt:Blogs>

    <mt:ResetPasswordURL>&return_to=<mt:Var name="return_to">

After the email body has been crafted with the `return_to` parameter, the "New Password Form" template must be updated to include this field. The following is found within this template; notice the addition of the last hidden input field.

    <form method="post" action="<mt:var name="script_url">">
    <input type="hidden" name="__mode" value="new_pw" />
    <input type="hidden" name="token" value="<mt:var name="token" escape="html">" />
    <input type="hidden" name="email" value="<mt:var name="email" escape="html">" />
    <input type="hidden" name="return_to" value="<mt:Var name="return_to" escape="html" />

After a user receives the renewal email and follows the link to change their password and activate their account, they will now be redirected to the `return_to` URL you specify


# Workflow

## Setting up a Role

Create a new Role to attach a timer to (at the System level go to Manage > Users, then Roles and Create Role). This way you can be sure not to affect your current users.

A Role can be automatically assigned when a registered user interacts with a blog. Select a blog and choose Manage > Users, then click "add a user to this blog." Select the "(newly created user)" option, click Continue, and select a role to be applied.

## The User Experience

Example: you've created a Trial Membership rule that disables Commenters after 30 days. Users are allowed to renew, and they are emailed a renewal link.

The required time elapses, Trial Membership changes the user's status from Enabled to Pending, and sends an email to the user. The user clicks the renewal/change password link in the email and follows through the process, creating a new password for themselves.

Upon successfully changing the password their account is re-enabled. If a custom field was specified in the Track Activations plugin setting, the number in that field is incremented by one. Also, within the `mt_author_meta` table the field `last_activated` is updated with the date and time they re-activated (this field is used to determine when the timer's rule has elapsed).

----

If a user is disabled and they do not receive a re-activation email (or if they've inadvertently deleted it, for example) they can simply go through the "Forgot Password?" process to reset their password, which will also update their status.

Note that if a user has been disabled (that is, the option "Allow the user to renew their access (set to status 'pending')" is not checked) they can no longer change the state of their account. It is disabled, and only an administrator can enable it.


# Caveats

There are a few "gotchas" to working with Trial Membership.

Any Role may be selected to create a rule, however be sure you recognize which users this will effect. You probably never want to select the Blog Administrator role for expiration. In fact, you could lock yourself out of MT this way! (However, the one safety net is that System Administrators can never be disabled by Trial Membership.)

Also note that if a user has two or more roles applied to them and one of them has a Trial Membership timer assigned to it, they can be disabled. In other words if a Blog Administrator is also a Commenter, and if the Commenter role has a Trial Membership timer, this user will be disabled.

Extending the previous example: if multiple rules are used (such as for Commenter and Author Roles), and if a user has those roles applied to them, both of these rules will affect them. Many roles and many timers can cause a bit of confusion here if you need to determine which timer is responsible for which activity.


