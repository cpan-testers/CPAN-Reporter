package CPAN::Reporter::Config;
# Not really a .pm file, but holds wikidoc which will be
# turned into .pod by the Build.PL
$VERSION = "0.99_01";
use strict; # make CPANTS happy
use File::HomeDir (); 
use File::Path (qw/mkpath/);
use File::Spec ();
use IO::File ();
use CPAN (); # for printing warnings

#--------------------------------------------------------------------------#
# Back-compatibility checks -- just once per load
#--------------------------------------------------------------------------#

# 0.28_51 changed Mac OS X config file location -- if old directory is found,
# move it to the new location
if ( $^O eq 'darwin' ) {
    my $old = File::Spec->catdir(File::HomeDir->my_documents,".cpanreporter");
    my $new = File::Spec->catdir(File::HomeDir->my_home,".cpanreporter");
    if ( ( -d $old ) && (! -d $new ) ) {
        $CPAN::Frontend->mywarn( << "HERE");
Since CPAN::Reporter 0.28_51, the Mac OSX config directory has changed. 

  Old: $old
  New: $new  

Your existing configuration file will be moved automatically.
HERE
        mkpath($new);
        my $OLD_CONFIG = IO::File->new(
            File::Spec->catfile($old, "config.ini"), "<"
        ) or die $!;
        my $NEW_CONFIG = IO::File->new(
            File::Spec->catfile($new, "config.ini"), ">"
        ) or die $!;
        $NEW_CONFIG->print( do { local $/; <$OLD_CONFIG> } );
        $OLD_CONFIG->close;
        $NEW_CONFIG->close;
        unlink File::Spec->catfile($old, "config.ini") or die $!;
        rmdir($old) or die $!;
    }
}
#--------------------------------------------------------------------------#
# _config_order -- determines order of interactive config.  Only items 
# in interactive config will be written to a starter config file
#--------------------------------------------------------------------------#

sub _config_order {
    return qw(  
        email_from 
        smtp_server 
        edit_report 
        send_report
    );
}

#--------------------------------------------------------------------------#
# _grade_action_prompt -- describes grade action pairs
#--------------------------------------------------------------------------#

sub _grade_action_prompt {
    return << 'HERE';

Some of the following configuration options require one or more "grade:action"
pairs that determine what grade-specific action to take for that option.
These pairs should be space-separated and are processed left-to-right. See
CPAN::Reporter documentation for more details.

    GRADE   :   ACTION  ======> EXAMPLES        
    -------     -------         --------    
    pass        yes             default:no
    fail        no              default:yes pass:no
    unknown     ask/no          default:ask/no pass:yes fail:no
    na          ask/yes         
    default

HERE
}

#--------------------------------------------------------------------------#
# _config_spec -- returns configuration options information
#
# Keys include
#   default     --  recommended value, used in prompts and as a fallback
#                   if an options is not set
#   prompt      --  short prompt for EU::MM prompting
#   info        --  long description shown before prompting
#   validate    --  CODE ref; return normalized option or undef if invalid
#--------------------------------------------------------------------------#

my %option_specs = (
    email_from => {
        default => '',
        prompt => 'What email address will be used for sending reports?',
        info => <<'HERE',
CPAN::Reporter requires a valid email address as the return address
for test reports sent to cpan-testers\@perl.org.  Either provide just
an email address, or put your real name in double-quote marks followed 
by your email address in angle marks, e.g. "John Doe" <jdoe@nowhere.com>.
Note: unless this email address is subscribed to the cpan-testers mailing
list, your test reports will not appear until manually reviewed.
HERE
    },
    cc_author => {
        default => 'default:yes pass/na:no',
        prompt => "Do you want to CC the the module author?",
        validate => \&_validate_grade_action_pair,
        info => <<'HERE',
If you would like, CPAN::Reporter will copy the module author with
the results of your tests.  By default, authors are copied only on 
failed/unknown results. This option takes "grade:action" pairs.  
HERE
    },
    edit_report => {
        default => 'default:ask/no pass/na:no',
        prompt => "Do you want to edit the test report?",
        validate => \&_validate_grade_action_pair,
        info => <<'HERE',
Before test reports are sent, you may want to edit the test report
and add additional comments about the result or about your system or
Perl configuration.  By default, CPAN::Reporter will ask after
each report is generated whether or not you would like to edit the 
report. This option takes "grade:action" pairs.
HERE
    },
    send_report => {
        default => 'default:ask/yes pass/na:yes',
        prompt => "Do you want to send the test report?",
        validate => \&_validate_grade_action_pair,
        info => <<'HERE',
By default, CPAN::Reporter will prompt you for confirmation that
the test report should be sent before actually emailing the 
report.  This gives the opportunity to bypass sending particular
reports if you need to (e.g. if you caused the failure).
This option takes "grade:action" pairs.
HERE
    },
    send_duplicates => {
        default => 'default:no',
        prompt => "This report is identical to a previous one.  Send it anyway?",
        validate => \&_validate_grade_action_pair,
        info => <<'HERE',
CPAN::Reporter records tests grades for each distribution, version and
platform.  By default, duplicates of previous results will not be sent at
all, regardless of the value of the "send_report" option.  This option takes 
"grade:action" pairs.
HERE
    },
    smtp_server => {
        default => undef, # not written to starter config
        info => <<'HERE',
If your computer is behind a firewall or your ISP blocks
outbound mail traffic, CPAN::Reporter will not be able to send
test reports unless you provide an alternate outbound (SMTP) 
email server.  Enter the full name of your outbound mail server
(e.g. smtp.your-ISP.com) or leave this blank to send mail 
directly to perl.org.  Use a space character to reset this value
to sending to perl.org.
HERE
    },
    email_to => {
        default => undef, # not written to starter config
    },
    editor => {
        default => undef, # not written to starter config
    },
    debug => {
        default => undef, # not written to starter config
    }
);

sub _config_spec { return %option_specs }

#--------------------------------------------------------------------------#
# _is_valid_action
#--------------------------------------------------------------------------#

my @valid_actions = qw{ yes no ask/yes ask/no ask };
sub _is_valid_action {
    my $action = shift;
    return grep { $action eq $_ } @valid_actions;
}

#--------------------------------------------------------------------------#
# _is_valid_grade
#--------------------------------------------------------------------------#

my @valid_grades = qw{ pass fail unknown na default };
sub _is_valid_grade {
    my $grade = shift;
    return grep { $grade eq $_ } @valid_grades;
}

#--------------------------------------------------------------------------#
# _validate_grade_action 
# returns hash of grade => action 
# returns undef
#--------------------------------------------------------------------------#

sub _validate_grade_action_pair {
    my ($name, $option) = @_;
    $option ||= "no";

    my %ga_map; # grade => action
    
    PAIR: for my $grade_action ( split q{ }, $option ) {
        my ($grade_list,$action);

        if ( $grade_action =~ m{.:.} ) {
            # parse pair for later check
            ($grade_list, $action) = $grade_action =~ m{\A([^:]+):(.+)\z};
        }
        elsif ( _is_valid_action($grade_action) ) {
            # action by itself
            $ga_map{default} = $grade_action;
            next PAIR;
        }
        elsif ( _is_valid_grade($grade_action) ) {
            # grade by itself
            $ga_map{$grade_action} = "yes";
            next PAIR;
        }
        elsif( $grade_action =~ m{./.} ) {
            # gradelist by itself, so setup for later check
            $grade_list = $grade_action;
            $action = "yes";
        }
        else {
            # something weird, so warn and skip
            $CPAN::Frontend->mywarn( 
                "\nIgnoring invalid grade:action '$grade_action' for '$name'.\n\n" 
            );
            next PAIR;
        }
        
        # check gradelist
        my %grades = map { ($_,1) } split( "/", $grade_list);
        for my $g ( keys %grades ) { 
            if ( ! _is_valid_grade($g) ) {
                $CPAN::Frontend->mywarn( 
                    "\nIgnoring invalid grade '$g' in '$grade_action' for '$name'.\n\n" 
                );
                delete $grades{$g};
            }
        }
        
        # check action
        if ( ! _is_valid_action($action) ) {
            $CPAN::Frontend->mywarn( 
                "\nIgnoring invalid action '$action' in '$grade_action' for '$name'.\n\n" 
            );
            next PAIR;
        }

        # otherwise, it all must be OK
        $ga_map{$_} = $action for keys %grades;
    }

    return scalar(keys %ga_map) ? \%ga_map : undef;
}

1;
__END__

=begin wikidoc

= NAME

CPAN::Reporter::Config - Config file options for CPAN::Reporter

= VERSION

This documentation refers to version %%VERSION%%

= SYNOPSIS

From the CPAN shell:

 cpan> o conf init test_report

= DESCRIPTION

Default options for CPAN::Reporter are read from a configuration file 
{.cpanreporter/config.ini} in the user's home directory (Unix and OS X)
or "My Documents" directory (Windows).

The configuration file is in "ini" format, with the option name and value
separated by an "=" sign

  email_from = "John Doe" <johndoe@nowhere.org>
  cc_author = no

Interactive configuration of email address, mail server and common
action prompts may be repeated at any time from the CPAN shell.  

 cpan> o conf init test_report

If a configuration file does not exist, it will be created the first
time interactive configuration is performed.

Subsequent interactive configuration will also include any advanced
options that have been added manually to the configuration file.

= INTERACTIVE CONFIGURATION OPTIONS

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

The action prompt options included in interactive configuration are:

* {edit_report = <grade:action> ...} -- edit the test report before sending? 
(default:ask/no pass/na:no)
* {send_report = <grade:action> ...} -- should test reports be sent at all?
(default:ask/yes pass/na:yes)

Note that if {send_report} is set to "no", CPAN::Reporter will still go through
the motions of preparing a report, but will discard it rather than send it.

A better way to disable CPAN::Reporter temporarily is with the CPAN option
{test_report}:

 cpan> o conf test_report 0

= ADVANCED CONFIGURATION OPTIONS

These additional options are only necessary in special cases, such as for
testing, debugging or if a default editor cannot be found.

* {editor = <editor>} -- editor to use to edit the test report; if not set,
Test::Reporter will use environment variables {VISUAL}, {EDITOR} or {EDIT}
(in that order) to find an editor 
* {cc_author = <grade:action> ...} -- should module authors should be sent a copy of 
the test report at their {author@cpan.org} address? (default:yes pass/na:no)
* {send_duplicates = <grade:action> ...} -- should duplicates of previous 
reports be sent, regardless of {send_report}? (default:no)
* {email_to = <email address>} -- alternate destination for reports instead of
{cpan-testers@perl.org}; used for testing
* {debug = <boolean>} -- turns debugging on/off

If these options are manually added to the configuration file, they will
be included (and preserved) in subsequent interactive configuration.

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

