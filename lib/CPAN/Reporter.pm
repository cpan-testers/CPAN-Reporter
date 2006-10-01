package CPAN::Reporter;
use strict;

$CPAN::Reporter::VERSION = $CPAN::Reporter::VERSION = "0.24";

use Config;
use Config::Tiny ();
use ExtUtils::MakeMaker qw/prompt/;
use File::Basename qw/basename/;
use File::HomeDir ();
use File::Path qw/mkpath/;
use File::Temp ();
use Probe::Perl ();
use Tee qw/tee/;
use Test::Reporter ();

#--------------------------------------------------------------------------#
# defaults and prompts
#--------------------------------------------------------------------------#

# undef defaults are not written to the starter configuration file

my @config_order = qw/ email_from cc_author edit_report send_report
                       smtp_server /;
my %defaults = (
    email_from => {
        default => '',
        prompt => 'What email address will be used for sending reports?',
        info => <<'HERE',
CPAN::Reporter requires a valid email address as the return address
for test reports sent to cpan-testers\@perl.org.  Either provide just
an email address, or put your real name in double-quote marks followed 
by your email address in angle marks, e.g. "John Doe" <jdoe@nowhere.com>
HERE
    },
    cc_author => {
        default => 'fail',
        prompt => "Do you want to CC the the module author?",
        info => <<'HERE',
If you would like, CPAN::Reporter will copy the module author with
the results of your tests.  By default, authors are copied only on 
failed/unknown results. This option takes a "yes/no/fail/ask" value.  
HERE
    },
    edit_report => {
        default => 'ask/no',
        prompt => "Do you want to edit the test report?",
        info => <<'HERE',
Before test reports are sent, you may want to edit the test report
and add additional comments about the result or about your system or
Perl configuration.  By default, CPAN::Reporter will ask after
each report is generated whether or not you would like to edit the 
report. This option takes a "yes/no/fail/ask" value.
HERE
    },
    send_report => {
        default => 'ask/yes',
        prompt => "Do you want to send the test report?",
        info => <<'HERE',
By default, CPAN::Reporter will prompt you for confirmation that
the test report should be sent before actually emailing the 
report.  This gives the opportunity to bypass sending particular
reports if you need to (e.g. a duplicate of an earlier result).
This option takes a "yes/no/fail/ask" value.
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
directly to perl.org.  Use a space character to reset an existing
default.
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
#--------------------------------------------------------------------------#
# public API
#--------------------------------------------------------------------------#

sub configure {
    my $config_dir = _get_config_dir();
    my $config_file = _get_config_file();

    mkpath $config_dir if ! -d $config_dir;

    my $config;
    my $existing_options;
    
    # read or create
    if ( -f $config_file ) {
        print "\nFound your CPAN::Reporter config file at '$config_file'.\n";
        $config = _open_config_file() 
            or return;
        $existing_options = _get_config_options( $config );
        print "\nUpdating your CPAN::Reporter configuration settings:\n"
    }
    else {
        print "\nNo CPAN::Reporter config file found; creating a new one.\n";
        $config = Config::Tiny->new();
    }
    
    # initialize options that have an info description
    for my $k ( @config_order ) {
        my $option_data = $defaults{$k};
        print "\n" . $option_data->{info}. "\n";
        if ( defined $defaults{$k}{default} ) {
            $config->{_}{$k} = prompt( 
                "$k?", 
                $existing_options->{$k} || $option_data->{default} 
            );
        }
        else {
            # only initialize options with undef default if
            # answer matches non white space, otherwise
            # reset it
            my $answer = prompt( 
                "$k?", 
                $existing_options->{$k} || q{} 
            ); 
            if ( $answer =~ /\S/ ) {
                $config->{_}{$k} = $answer;
            }
            else {
                delete $config->{_}{$k};
            }
        }
        # delete existing as we proceed so we know what's left
        delete $existing_options->{$k};
    }

    # initialize remaining existing options
    print "\nYour CPAN::Reporter config file also contains these advanced " .
          "options:\n\n" if keys %$existing_options;
    for my $k ( keys %$existing_options ) {
        $config->{_}{$k} = prompt( "$k?", $existing_options->{$k} ); 
    }

    print "\nWriting CPAN::Reporter config file to '$config_file'.\n";    
    if ( $config->write( $config_file ) ) {
        return $config->{_};
    }
    else {
        warn "\nError writing config file to '$config_file':" . 
             Config::Tiny->errstr(). "\n";
        return;
    }
}

sub test {
    my ($dist, $system_command) = @_;
    my $temp_out = File::Temp->new;
    
    my $result = {
        dist => $dist,
        command => $system_command,
    };

    my ($tee_input, $makewrapper);
    
    if ( -f "test.pl" && _is_make($system_command) ) {
        $makewrapper = File::Temp->new;
        open MAKEWRAP, ">$makewrapper"
            or die "Could not create a wrapper for make: $!";
        print MAKEWRAP qq{system('$system_command');\n};
        print MAKEWRAP qq{print "makewrapper: make ", \$? ? "failed" : "ok";\n};
        close MAKEWRAP;
        $tee_input = Probe::Perl->find_perl_interpreter() .  " $makewrapper";
    }
    else {
        $tee_input = $system_command;
    }
    
    tee($tee_input, { stderr => 1 }, $temp_out);
        
    if ( ! open(TEST_RESULT, "<", $temp_out) ) {
        warn "CPAN::Reporter couldn't read test results\n";
        return;
    }
    $result->{output} = do { local $/; <TEST_RESULT> };
    close TEST_RESULT;

    _process_report( $result );
    return $result->{success};    
}

#--------------------------------------------------------------------------#
# private functions
#--------------------------------------------------------------------------#

sub _get_config_dir {
    return File::Spec->catdir(File::HomeDir->my_documents, ".cpanreporter");
}

#--------------------------------------------------------------------------#

sub _get_config_file {
    return File::Spec->catdir( _get_config_dir, "config.ini" );
}

#--------------------------------------------------------------------------#

sub _get_config_options {
    my $config = shift;
    # extract and return valid options, with fallback to defaults
    my %active;
    for my $option ( keys %defaults ) {
        if ( exists $config->{_}{$option} ) {
            $active{$option} = $config->{_}{$option};
        }
        else {
            $active{$option} = $defaults{$option}{default}
                if defined $defaults{$option}{default};
        }
    }
    return \%active;
}

#--------------------------------------------------------------------------#

sub _grade_msg {
    my ($grade, $msg) = @_;
    print "Test result is '$grade'";
    print ": $msg" if defined $msg && length $msg;
    print ".\n";
    return;
}

#--------------------------------------------------------------------------#

sub _grade_report {
    my $result = shift;
    my ($grade,$is_make,$msg);

    # CPAN.pm won't normally test a failed 'make', so that should
    # catch prereq failures that would normally be "unknown".
    # XXX really should check in case test was forced
    #
    # Output strings taken from Test::Harness::
    # _show_results()  -- for versions < 2.57_03 
    # get_results()    -- for versions >= 2.57_03

    # check for make or Build
    $is_make = _is_make( $result->{command} );
        
    # parse for Test::Harness results
    if ( $result->{output} =~ m{^All tests successful}ms ) {
        $grade = 'pass';
        $msg = 'All tests successful';
    }
    elsif ( $result->{output} =~ m{^.?No tests defined}ms ) {
        $grade = 'unknown';
        $msg = 'No tests provided';
    }
    elsif ( $result->{output} =~ m{^FAILED--no tests were run}ms ) {
        $grade = 'unknown';
        $msg = 'No tests were run';
    }
    elsif ( $result->{output} =~ m{^FAILED--.*--no output}ms ) {
        $grade = 'fail';
        $msg = 'Tests had no output';
    }
    elsif ( $result->{output} =~ m{^Failed }ms ) {  # must be lowercase
        $grade = 'fail';
        $msg = "Distribution had failing tests";
    }
    else {
        # didn't find Test::Harness output we recognized
        $grade = "unknown";
        $msg = "Couldn't determine a result";
    }

    # With test.pl and 'make test', any t/*.t might pass Test::Harness, but
    # test.pl might still fail, or there might only be test.pl,
    # so re-run make test on test.pl
    
    if ( $is_make && -f "test.pl" && $grade ne 'fail' ) {
        if ( $result->{output} =~ m{^makewrapper: make failed}ims ) {
            $grade = "fail";
            $msg = "'make test' error detected";
        }
        else {
            $grade = "pass";
            $msg = "'make test' no errors";
        }
    }

    # Downgrade failure if we can determine a cause of the failure
    # that should be reported as 'na'

    if ( $grade eq 'fail' ) {
        # check the prereq report for a failure flag (!)
        if ( $result->{prereq_pm} =~ m{n/a}ims ) {
            $grade = 'na';
            $msg = 'Prerequisite missing';
        }
        elsif ( $result->{prereq_pm} =~ m{^\s+!}ims ) {
            $grade = 'na';
            $msg = 'Prerequisite version too low';
        }
        elsif ( $result->{output} =~ m{Perl .*? required.*?this is only}ms ) {
            $grade = 'na';
            $msg = 'Perl version too low';
        }
    }

    _grade_msg( $grade, $msg );
    return $grade;
}

#--------------------------------------------------------------------------#

sub _is_make {
    my $command = shift;
    return 1 if $command =~ m{^\S*make}ims;
}

#--------------------------------------------------------------------------#

sub _open_config_file {
    my $config_file = _get_config_file();
    my $config = Config::Tiny->read( $config_file )
        or warn "Couldn't read CPAN::Reporter configuration file " .
                "'$config_file': " . Config::Tiny->errstr() . "\n";
    return $config; 
}

#--------------------------------------------------------------------------#

sub _prereq_report {
    my $data = shift;
    my %prereq;
    $prereq{requires} = $data->{dist}->prereq_pm;
    
    # unpack if subdivided in newer versions of CPAN.pm
    if ( 
        join( q{ }, sort keys %{$prereq{requires}} ) eq 
        "build_requires requires" 
    ) {
        $prereq{build_requires} = $prereq{requires}{build_requires};
        $prereq{requires} = $prereq{requires}{requires};
    }

    my ($name_width, $need_width, $have_width) = (6, 4, 4);
    my (%have, $report);

    # find formatting widths and get installed versions
    for my $section ( qw/requires build_requires/ ) {
        for my $module ( keys %{ $prereq{$section} } ) {
            my $name_length = length $module;
            my $need_length = length $prereq{$section}{$module};
            my $version = eval "require $module; return $module->VERSION";
            $version = defined $version ? $version : "n/a";
            my $have_length = length $version;
            $have{$module} = $version;
            $name_width = $name_length if $name_length > $name_width;
            $need_width = $need_length if $need_length > $need_width;
            $have_width = $have_length if $have_length > $have_width;
        }
    }

    my $format_str = 
        "  \%1s \%-${name_width}s \%-${need_width}s \%-${have_width}s\n";

    # generate the report
    for my $section ( qw/requires build_requires/ ) {
        if ( keys %{ $prereq{$section} } ) {
            $report .= "$section:\n\n";
            $report .= sprintf( $format_str, " ", qw/Module Need Have/ );
            $report .= sprintf( $format_str, " ", 
                                 "-" x $name_width, 
                                 "-" x $need_width,
                                 "-" x $have_width );
        }
        for my $module ( keys %{ $prereq{$section} } ) {
            my $need = $prereq{$section}{$module};
            # can we satisfy the prereq?
            eval "use $module $need";
            # flag bad modules with "!" and for parsing later
            my $bad = $@ ? "!" : " ";
            $report .= 
                sprintf( $format_str, $bad, $module, $need, $have{$module});
        }
        print "\n";
    }
    
    
    return $report || "    No requirements found\n";
}

#--------------------------------------------------------------------------#

sub _process_report {
    my ( $result ) = @_;

    # Get configuration options
    my $config_obj = _open_config_file();
    if ( not defined $config_obj ) {
        warn "\nCPAN::Reporter config file not found. " .
             "Skipping test report generation.\n";
        return;
    }
    my $config = _get_config_options( $config_obj );
    
    if ( ! $config->{email_from} ) {
        warn << "EMAIL_REQUIRED";
        
CPAN::Reporter requires an email-address.  Test report will not be sent.
See documentation for configuration details.

EMAIL_REQUIRED
        return;
    }
        
    # Setup variables for use in report
    $result->{dist_name} = basename($result->{dist}->pretty_id);
    $result->{dist_name} =~ s/(\.tar\.gz|\.tgz|\.zip)$//i;
    $result->{author} = $result->{dist}->author->fullname;
    $result->{author_id} = $result->{dist}->author->id;
    $result->{prereq_pm} = _prereq_report( $result );

    # Determine result
    print "Preparing a test report for $result->{dist_name}\n";
    $result->{grade} = _grade_report($result);
    $result->{success} =  $result->{grade} eq 'pass'
                       || $result->{grade} eq 'unknown';

    # Setup the test report
    my $tr = Test::Reporter->new;
    $tr->grade( $result->{grade} );
    $tr->debug( $config->{debug} ) if defined $config->{debug};
    $tr->from( $config->{email_from} );
    $tr->address( $config->{email_to} ) if $config->{email_to};
    if ( $config->{smtp_server} ) {
        my @mx = split " ", $config->{smtp_server};
        $tr->mx( \@mx );
    }
    
    # Populate the test report
    
    $tr->distribution( $result->{dist_name}  );
    $tr->comments( _report_text( $result ) );
    $tr->via( 'CPAN::Reporter ' . $CPAN::Reporter::VERSION );
    my @cc;

    # User prompts for action
    if ( _prompt( $config, "cc_author", $tr->grade) =~ /^y/ ) {
        push @cc, "$result->{author_id}\@cpan.org";
    }
    
    if ( _prompt( $config, "edit_report", $tr->grade ) =~ /^y/ ) {
        my $editor = $config->{editor};
        local $ENV{VISUAL} = $editor if $editor;
        $tr->edit_comments;
    }
    
    if ( _prompt( $config, "send_report", $tr->grade ) =~ /^y/ ) {
        print "Sending test report with '" . $tr->grade . 
              "' to " . join(q{, }, $tr->address, @cc) . "\n";
        $tr->send( @cc ) or warn $tr->errstr. "\n";
    }
    else {
        print "Test report not sent\n";
    }

    return;
}

#--------------------------------------------------------------------------#
# _prompt
#
# Note: always returns lowercase
#--------------------------------------------------------------------------#

sub _prompt {
    my ($config, $option, $grade) = @_;
    my $prompt;
    if     ( lc $config->{$option} eq 'ask/yes' ) { 
        $prompt = prompt( $defaults{$option}{prompt} . " (yes/no)", "yes" );
    }
    elsif  ( $config->{$option} =~ m{^ask(/no)?}i ) {
        $prompt = prompt( $defaults{$option}{prompt} . " (yes/no)", "no" );
    }
    elsif  ( lc $config->{$option} =~ 'fail' ) {
        $prompt = ( $grade =~ m{^(fail|unknown)$}i ) ? 'yes' : 'no';
    }
    else { 
        $prompt = $config->{$option};
    }
    return lc $prompt;
}

#--------------------------------------------------------------------------#

sub _report_text {
    my $data = shift;
    
    # generate report
    my $output = << "ENDREPORT";
Dear $data->{author},
    
This is a computer-generated test report for $data->{dist_name}, created
automatically by CPAN::Reporter, version $CPAN::Reporter::VERSION.

ENDREPORT
    
    if ( $data->{success} ) { $output .= << "ENDREPORT"; 
Thank you for uploading your work to CPAN.  Congratulations!
All tests were successful.

ENDREPORT
    }
    else { $output .=  <<"ENDREPORT";
Thank you for uploading your work to CPAN.  However, it appears that
there were some problems testing your distribution.

ENDREPORT
    }
    $output .= << "ENDREPORT";
Sections of this report:

    * Tester comments
    * Prerequisites
    * Test output

------------------------------
TESTER COMMENTS
------------------------------

Additional comments from tester: 

[none provided]

------------------------------
PREREQUISITES
------------------------------

Prerequisite modules loaded:

$data->{prereq_pm}
------------------------------
TEST OUTPUT
------------------------------

Output from '$data->{command}':

$data->{output}
ENDREPORT

    return $output;
}

1; #this line is important and will help the module return a true value

__END__

#--------------------------------------------------------------------------#
# pod documentation 
#--------------------------------------------------------------------------#

=begin wikidoc

= NAME

CPAN::Reporter - Provides Test::Reporter support for CPAN.pm

= VERSION

This documentation describes version %%VERSION%%.

= SYNOPSIS

From the CPAN shell:

 cpan> install CPAN::Reporter
 cpan> reload cpan
 cpan> o conf init test_report

= DESCRIPTION

CPAN::Reporter is an add-on for the CPAN.pm module that uses
[Test::Reporter] to send the results of module tests to the CPAN
Testers project.  Support for CPAN::Reporter is available in CPAN.pm 
as of version 1.88.

The goal of the CPAN Testers project ( [http://testers.cpan.org/] ) is to
test as many CPAN packages as possible on as many platforms as
possible.  This provides valuable feedback to module authors and
potential users to identify bugs or platform compatibility issues and
improves the overall quality and value of CPAN.

One way individuals can contribute is to send test results for each module that
they test or install.  Installing CPAN::Reporter gives the option of
automatically generating and emailing test reports whenever tests are run via
CPAN.pm.

= GETTING STARTED

The first step in using CPAN::Reporter is to install it using whatever
version of CPAN.pm is already installed.  CPAN.pm will be upgraded as
a dependency if necessary.

 cpan> install CPAN::Reporter

If CPAN.pm was upgraded, it needs to be reloaded.

 cpan> reload cpan

If upgrading from a very old version of CPAN.pm, users may be prompted to renew
their configuration settings, including the 'test_report' option to enable
CPAN::Reporter.  

If not prompted automatically, users should manually initialize CPAN::Reporter
support.  After enabling CPAN::Reporter,  CPAN.pm will automatically continue
with interactive configuration of CPAN::Reporter options.

 cpan> o conf init test_report

Once CPAN::Reporter is enabled and configured, test or install modules with
CPAN.pm as usual.

= UNDERSTANDING TEST GRADES

CPAN::Reporter will assign one of the following grades to the report:

* {pass} -- all tests were successful  

* {fail} -- one or more tests failed, one or more test files died during
testing or no test output was seen

* {na} -- tests could not be run on this platform or one or more test files
died because of missing prerequisites

* {unknown} -- no test files could be found (either t/*.t or test.pl) or 
a result could not be determined from test output

In returning results to CPAN.pm, "pass" and "unknown" are considered successful
attempts to "make test" or "Build test" and will not prevent installation.
"fail" and "na" are considered to be failures and CPAN.pm will not install
unless forced.

= CONFIG FILE OPTIONS

Default options for CPAN::Reporter are read from a configuration file 
{.cpanreporter/config.ini} in the user's home directory (Unix), "My 
Documents" directory (Windows) or "~/Documents" directory (OS X).  
(See [File::HomeDir] and the {my_documents} method for config folder
location on other operating systems.)

The configuration file is in "ini" format, with the option name and value
separated by an "=" sign

  email_from = "John Doe" <johndoe@nowhere.org>
  cc_author = no

Options shown below as taking "yes/no/fail/ask" should be set to one of
five values; the result of each is as follows:

* {yes} -- automatic yes
* {no} -- automatic no
* {fail} -- yes if the test result was failure/unknown; no otherwise
* {ask/no} or just {ask} -- prompt each time, but default to no
* {ask/yes} -- prompt each time, but default to yes

For prompts, the default will be used if return is pressed immediately at
the prompt or if the {PERL_MM_USE_DEFAULT} environment variable is set to
a true value.

Interactive configuration of required and standard options may be repeated at
any time from the CPAN shell.  Interactive configuration will also includes 
any additional options that already exist within the configuration file.

 cpan> o conf init test_report

Descriptions for each option follow.

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

== Standard Options

These options are included in the standard config file template that is
automatically created.

* {cc_author = yes/no/fail/ask} -- should module authors should be sent a copy of 
the test report at their {author@cpan.org} address (default: fail)
* {edit_report = yes/no/fail/ask} -- edit the test report before sending 
(default: ask/no)
* {send_report = yes/no/fail/ask} -- should test reports be sent at all 
(default: ask/yes)
* {smtp_server = <server list>} -- one or more alternate outbound mail servers
if the default perl.org mail servers cannot be reached (e.g. users behind a 
firewall); multiple servers may be given, separated with a space 
(default: none)

Note that if {send_report} is set to "no", CPAN::Reporter will still go through
the motions of preparing a report, but will discard it rather than send it.
This is used for testing CPAN::Reporter.

A better way to disable CPAN::Reporter temporarily is with the CPAN option
{test_report}:

 cpan> o conf test_report 0
 
== Additional Options

These additional options are only necessary in special cases, such as for
testing, debugging or if a default editor cannot be found.

* {email_to = <email address>} -- alternate destination for reports instead of
{cpan-testers@perl.org}; used for testing (default: none)
* {editor = <editor>} -- editor to use to edit the test report; if not set,
Test::Reporter will use environment variables {VISUAL}, {EDITOR} or {EDIT}
(in that order) to find an editor (default: none)
* {debug = <boolean>} -- turns debugging on/off (default: off)

= FUNCTIONS

CPAN::Reporter provides only two public function for use within CPAN.pm.
They are not imported during {use}.  Ordinary users will never need them.

== {configure()}

 CPAN::Reporter::configure();

Prompts the user to edit configuration settings stored in the CPAN::Reporter
{config.ini} file.  It will create the configuration file if it does not exist.
It is automatically called by CPAN.pm when initializing the 'test_report'
option, e.g.:

 cpan> o conf init test_report

== {test()}

 CPAN::Reporter::test( $cpan_dist, $system_command );

Given a CPAN::Distribution object and a system command to run distribution
tests (e.g. "make test"), {test()} executes the command via {system()} while
teeing the output to a file.  Based on the output captured in the file,
{test()} generates and sends a [Test::Reporter] report.  It returns true if
the test grade is "pass" or "unknown" and returns false, otherwise.

= BUGS

Please report any bugs or feature using the CPAN Request Tracker.  
Bugs can be submitted by email to bug-CPAN-Reporter@rt.cpan.org or 
through the web interface at 
[http://rt.cpan.org/Dist/Display.html?Queue=CPAN-Reporter]

When submitting a bug or request, please include a test-file or a patch to an
existing test-file that illustrates the bug or desired feature.

= AUTHOR

David A. Golden (DAGOLDEN)

dagolden@cpan.org

http://www.dagolden.org/

= COPYRIGHT AND LICENSE

Copyright (c) 2006 by David A. Golden

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

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

=cut
