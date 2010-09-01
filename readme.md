# Trial Membership Overview

The Trial Membership plugin for Movable Type and Melody can be used to disable users after a specified amount of time has elapsed. In other words, Commenters or Contributors (for example) can be allowed to participate and interact with your site for only a specified amount of time -- a trial membership.

Create a "rule" by selecting a Role and specifying a number of days to elapse. A user's status will be changed to Disabled after that specified time has elapsed and if they belong to the specified role. Many "rules" can be created to target different groups of users. Stay abreast of which users have been disabled with email notification.

A task runs periodically to disable any users that meet the specified rules.


# Prerequisites

* Movable Type 4.x


# Installation

This plugin is installed [just like any other Movable Type Plugin](http://www.majordojo.com/2008/12/the-ultimate-guide-to-installing-movable-type-plugins.php).


# Using Trial Membership

This plugin add a single Page Action to the "Users: System-wide" screen, labeled Trial Membership. Select it to work with roles and timers.

To create a timer rule, select a role and specify a number of days. Any user who has the selected role applied to them, and for which the specified number of days have passed since the user was created, will be disabled. Use the "add another rule" button to create more rules.

Specify an email address to be notified when any users have been disabled. This field can be left blank to suppress email; notification will still be recorded to the Activity Log.

The rules you define are used with Movable Type's Tasks framework. Be sure you have `run-periodic-tasks` set up to cause tasks to run on schedule.

## Caveats

Any Role may be selected to create a rule, however be sure you recognize which users this will effect. You probably never want to select the Blog Administrator role for expiration. In fact, you could lock yourself out of MT this way! (However, the one safety net is that System Administrators can never be disabled by Trial Membership.)

Also note that if a user has two roles applied to them and one of them has a Trial Membership timer assigned to it, they can be disabled. In other words if a Blog Administrator is also a Commenter, and if the Commenter role has a Trial Membership timer, this user will be disabled.

## Suggested Workflow

Create a new Role to attach a timer to (at the System level go to Manage > Users, then Roles and Create Role). This way you can be sure not to affect your current users.

A Role can be automatically assigned when a registered user interacts with a blog. Select a blog and choose Manage > Users, then click "add a user to this blog." Select the "(newly created user)" option, click Continue, and select a role to be applied.

When a Trial Membership rule is run and a user is disabled, you may want to enable them again. Note that simply changing the user's status to "Enabled" is not enough! Because the user still has the same role(s) applied, they will be disabled the next time Trial Membership's task runs. You must assign the user to a different Role to prevent them from being disabled again.

