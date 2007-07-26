package CPAN::Reporter::Config;
# Not really a .pm file, but holds wikidoc which will be
# turned into .pod by the Build.PL
$VERSION = "0.47_01";
use strict; # make CPANTS happy
1;
__END__

=begin wikidoc

= NAME

CPAN::Reporter::Config - Config file options for CPAN::Reporter

= VERSION

This documentation refers to version %%VERSION%%

= CONFIG FILE OPTIONS

Default options for CPAN::Reporter are read from a configuration file 
{.cpanreporter/config.ini} in the user's home directory (Unix and OS X)
or "My Documents" directory (Windows).

The configuration file is in "ini" format, with the option name and value
separated by an "=" sign

  email_from = "John Doe" <johndoe@nowhere.org>
  cc_author = no

Interactive configuration of email address, action prompts and mail server
options may be repeated at any time from the CPAN shell.  

 cpan> o conf init test_report

Interactive configuration will also include any additional, non-standard
options that have been added manually to the configuration file.

Available options are described in the following sections.

== Email Address (required)

CPAN::Reporter requires users to provide an email address that will be used
in the "From" header of the email to cpan-testers@perl.org.

* {email_from = <email address>} -- email address of the user sending the
test report; it should be a valid address format, e.g.:

 user@domain
 John Doe <user@domain>
 "John Q. Public" <user@domain>

Because {cpan-testers} uses a mailing list to collect test reports, it is
helpful if the email address provided is subscribed to the list.  Otherwise,
test reports will be held until manually reviewed and approved.  

Subscribing an account to the cpan-testers list is as easy as sending a blank
email to cpan-testers-subscribe@perl.org and replying to the confirmation
email.

== Action Prompts

Several steps in the generation of a test report are optional.  Configuration
options control whether an action should be taken automatically or whether
CPAN::Reporter should prompt the user for the action to take.  The action
to take may be different for each report grade.

Valid actions, and their associated meaning, are as follows:

* {yes} -- automatic yes
* {no} -- automatic no
* {ask/no} or just {ask} -- ask each time, but default to no
* {ask/yes} -- ask each time, but default to yes

For "ask" prompts, the default will be used if return is pressed immediately at
the prompt or if the {PERL_MM_USE_DEFAULT} environment variable is set to a
true value.

Action prompt options take one or more space-separated "grade:action" pairs,
which are processed left to right.

 edit_report = fail:ask/yes pass:no
 
An action by itself is taken as a default to be used for any grade which does
not have a grade-specific action.  A default action may also be set by using
the word "default" in place of a grade.  

 edit_report = ask/no
 edit_report = default:ask/no
 
A grade by itself is taken to have the action "yes" for that grade.

 edit_report = default:no fail

Multiple grades may be specified together by separating them with a slash.

 edit_report = pass:no fail/na/unknown:ask/yes

The action prompt options are:

* {cc_author = <grade:action> ...} -- should module authors should be sent a copy of 
the test report at their {author@cpan.org} address? (default:yes pass/na:no)
* {edit_report = <grade:action> ...} -- edit the test report before sending? 
(default:ask/no pass/na:no)
* {send_report = <grade:action> ...} -- should test reports be sent at all?
(default:ask/yes pass/na:yes)
* {send_duplicates = <grade:action> ...} -- should duplicates of previous 
reports be sent, regardless of {send_report}? (default:no)

These options are included in the starter config file created automatically the
first time CPAN::Reporter is configured interactively.

Note that if {send_report} is set to "no", CPAN::Reporter will still go through
the motions of preparing a report, but will discard it rather than send it.

A better way to disable CPAN::Reporter temporarily is with the CPAN option
{test_report}:

 cpan> o conf test_report 0

== Mail Server

By default, Test::Reporter attempts to send mail directly to perl.org mail 
servers.  This may fail if a user's computer is behind a network firewall 
that blocks outbound email.  In this case, the following option should
be set to the outbound mail server (i.e., SMTP server) as provided by
the user's Internet service provider (ISP):

* {smtp_server = <server list>} -- one or more alternate outbound mail servers
if the default perl.org mail servers cannot be reached; multiple servers may be
given, separated with a space (none by default)

In at least one reported case, an ISP's outbound mail servers also refused 
to forward mail unless the {email_from} was from the ISP-given email address. 

This option is also included in the starter config file.

== Additional Options

These additional options are only necessary in special cases, such as for
testing, debugging or if a default editor cannot be found.

* {email_to = <email address>} -- alternate destination for reports instead of
{cpan-testers@perl.org}; used for testing
* {editor = <editor>} -- editor to use to edit the test report; if not set,
Test::Reporter will use environment variables {VISUAL}, {EDITOR} or {EDIT}
(in that order) to find an editor 
* {debug = <boolean>} -- turns debugging on/off

= SEE ALSO

* [CPAN::Reporter]
* [CPAN::Reporter::FAQ]

= AUTHOR

David A. Golden (DAGOLDEN)

dagolden@cpan.org

http://dagolden.com/

= COPYRIGHT AND LICENSE

Copyright (c) 2006, 2007 by David A. Golden

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with
this module.

= DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=end wikidoc

