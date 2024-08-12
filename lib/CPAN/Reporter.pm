use strict;
package CPAN::Reporter;

our $VERSION = '1.2019';

use Config;
use Capture::Tiny qw/ capture tee_merged /;
use CPAN 1.94 ();
#CPAN.pm was split into separate files in this version
#set minimum to it for simplicity
use CPAN::Version ();
use File::Basename qw/basename dirname/;
use File::Find ();
use File::HomeDir ();
use File::Path qw/mkpath rmtree/;
use File::Spec 3.19 ();
use File::Temp 0.16 qw/tempdir/;
use IO::File ();
use Parse::CPAN::Meta ();
use Probe::Perl ();
use Test::Reporter 1.54 ();
use CPAN::Reporter::Config ();
use CPAN::Reporter::History ();
use CPAN::Reporter::PrereqCheck ();

use constant MAX_OUTPUT_LENGTH => 1_000_000;

#--------------------------------------------------------------------------#
# create temp lib dir for Devel::Autoflush
# so that PERL5OPT=-MDevel::Autoflush is found by any perl
#--------------------------------------------------------------------------#

use Devel::Autoflush 0.04 ();
# directory fixture
my $Autoflush_Lib = tempdir(
  "CPAN-Reporter-lib-XXXX", TMPDIR => 1, CLEANUP => 1
);
# copy Devel::Autoflush to directory or clear autoflush_lib variable
_file_copy_quiet(
  $INC{'Devel/Autoflush.pm'},
  File::Spec->catfile( $Autoflush_Lib, qw/Devel Autoflush.pm/ )
) or undef $Autoflush_Lib;

#--------------------------------------------------------------------------#
# public API
#--------------------------------------------------------------------------#

sub configure {
    goto &CPAN::Reporter::Config::_configure;
}

sub grade_make {
    my @args = @_;
    my $result = _init_result( 'make', @args ) or return;
    _compute_make_grade($result);
    if ( $result->{grade} eq 'discard' ) {
        $CPAN::Frontend->myprint(
            "\nCPAN::Reporter: test results were not valid, $result->{grade_msg}.\n\n",
            $result->{prereq_pm}, "\n",
            "Test report will not be sent"
        );
        CPAN::Reporter::History::_record_history( $result )
            if not CPAN::Reporter::History::_is_duplicate( $result );
    }
    else {
        _print_grade_msg($result->{make_cmd}, $result);
        if ( $result->{grade} ne 'pass' ) { _dispatch_report( $result ) }
    }
    return $result->{success};
}

sub grade_PL {
    my @args = @_;
    my $result = _init_result( 'PL', @args ) or return;
    _compute_PL_grade($result);
    if ( $result->{grade} eq 'discard' ) {
        $CPAN::Frontend->myprint(
            "\nCPAN::Reporter: test results were not valid, $result->{grade_msg}.\n\n",
            $result->{prereq_pm}, "\n",
            "Test report will not be sent"
        );
        CPAN::Reporter::History::_record_history( $result )
            if not CPAN::Reporter::History::_is_duplicate( $result );
    }
    else {
        _print_grade_msg($result->{PL_file} , $result);
        if ( $result->{grade} ne 'pass' ) { _dispatch_report( $result ) }
    }
    return $result->{success};
}

sub grade_test {
    my @args = @_;
    my $result = _init_result( 'test', @args ) or return;
    _compute_test_grade($result);
    if ( $result->{grade} eq 'discard' ) {
        $CPAN::Frontend->myprint(
            "\nCPAN::Reporter: test results were not valid, $result->{grade_msg}.\n\n",
            $result->{prereq_pm}, "\n",
            "Test report will not be sent"
        );
        CPAN::Reporter::History::_record_history( $result )
            if not CPAN::Reporter::History::_is_duplicate( $result );
    }
    else {
        _print_grade_msg( "Test", $result );
        _dispatch_report( $result );
    }
    return $result->{success};
}

sub record_command {
    my ($command, $timeout) = @_;

    # XXX refactor this!
    # Get configuration options
    if ( -r CPAN::Reporter::Config::_get_config_file() ) {
        my $config_obj = CPAN::Reporter::Config::_open_config_file();
        my $config;
        $config = CPAN::Reporter::Config::_get_config_options( $config_obj )
            if $config_obj;

        $timeout ||= $config->{command_timeout}; # might still be undef
    }

    my ($cmd, $redirect) = _split_redirect($command);

    # Teeing a command loses its exit value so we must wrap the command
    # and print the exit code so we can read it off of output
    my $wrap_code;
    if ( $timeout ) {
        $wrap_code = $^O eq 'MSWin32'
                   ? _timeout_wrapper_win32($cmd, $timeout)
                   : _timeout_wrapper($cmd, $timeout);
    }
    # if no timeout or timeout wrap code wasn't available
    if ( ! $wrap_code ) {
        my $safecmd = quotemeta($cmd);
        $wrap_code = << "HERE";
my \$rc = system("$safecmd");
my \$ec = \$rc == -1 ? -1 : \$?;
print "($safecmd exited with \$ec)\\n";
HERE
    }

    # write code to a tempfile for execution
    my $wrapper_name = _temp_filename( 'CPAN-Reporter-CW-' );
    my $wrapper_fh = IO::File->new( $wrapper_name, 'w' )
        or die "Could not create a wrapper for $cmd\: $!";

    $wrapper_fh->print( $wrap_code );
    $wrapper_fh->close;

    # tee the command wrapper
    my @tee_input = ( Probe::Perl->find_perl_interpreter, $wrapper_name );
    push @tee_input, $redirect if defined $redirect;
    my $tee_out;
    {
      # ensure autoflush if we can
      local $ENV{PERL5OPT} = _get_perl5opt() if _is_PL($command);
      $tee_out = tee_merged { system( @tee_input ) };
    }

    # cleanup
    unlink $wrapper_name unless $ENV{PERL_CR_NO_CLEANUP};

    my @cmd_output = split qr{(?<=$/)}, $tee_out;
    if ( ! @cmd_output ) {
        $CPAN::Frontend->mywarn(
            "CPAN::Reporter: didn't capture command results for '$cmd'\n"
        );
        return;
    }

    # extract the exit value
    my $exit_value;
    if ( $cmd_output[-1] =~ m{exited with} ) {
        ($exit_value) = $cmd_output[-1] =~ m{exited with ([-0-9]+)};
        pop @cmd_output;
    }

    # bail out on some errors
    if ( ! defined $exit_value ) {
        $CPAN::Frontend->mywarn(
            "CPAN::Reporter: couldn't determine exit value for '$cmd'\n"
        );
        return;
    }
    elsif ( $exit_value == -1 ) {
        $CPAN::Frontend->mywarn(
            "CPAN::Reporter: couldn't execute '$cmd'\n"
        );
        return;
    }

    return \@cmd_output, $exit_value;
}

sub test {
    my ($dist, $system_command) = @_;
    my ($output, $exit_value) = record_command( $system_command );
    return grade_test( $dist, $system_command, $output, $exit_value );
}

#--------------------------------------------------------------------------#
# private functions
#--------------------------------------------------------------------------#

#--------------------------------------------------------------------------#
# _compute_make_grade
#--------------------------------------------------------------------------#

sub _compute_make_grade {
    my $result = shift;
    my ($grade,$msg);
    if ( $result->{exit_value} ) {
        $result->{grade} = "unknown";
        $result->{grade_msg} = "Stopped with an error"
    }
    else {
        $result->{grade} = "pass";
        $result->{grade_msg} = "No errors"
    }

    _downgrade_known_causes( $result );

    $result->{success} =  $result->{grade} eq 'pass';
    return;
}

#--------------------------------------------------------------------------#
# _compute_PL_grade
#--------------------------------------------------------------------------#

sub _compute_PL_grade {
    my $result = shift;
    my ($grade,$msg);
    if ( $result->{exit_value} ) {
        $result->{grade} = "unknown";
        $result->{grade_msg} = "Stopped with an error"
    }
    else {
        $result->{grade} = "pass";
        $result->{grade_msg} = "No errors"
    }

    _downgrade_known_causes( $result );

    $result->{success} =  $result->{grade} eq 'pass';
    return;
}

#--------------------------------------------------------------------------#
# _compute_test_grade
#
# Don't shortcut to unknown unless _has_tests because a custom
# Makefile.PL or Build.PL might define tests in a non-standard way
#
# With test.pl and 'make test', any t/*.t might pass Test::Harness, but
# test.pl might still fail, or there might only be test.pl,
# so use exit code directly
#
# Likewise, if we have recursive Makefile.PL, then we don't trust the
# reverse-order parsing and should just take the exit code directly
#
# Otherwise, parse in reverse order for Test::Harness output or a couple
# other significant strings and stop after the first match.  Going in
# reverse and stopping is done to (hopefully) avoid picking up spurious
# results from any test output.  But then we have to check for
# unsupported OS strings in case those were printed but were not fatal.
#--------------------------------------------------------------------------#

sub _compute_test_grade {
    my $result = shift;
    my ($grade,$msg);
    my $output = $result->{output};

    # In some cases, get a result straight from the exit code
    if ( $result->{is_make} && ( -f "test.pl" || _has_recursive_make() ) ) {
        if ( $result->{exit_value} ) {
            $grade = "fail";
            $msg = "'make test' error detected";
        }
        else {
            $grade = "pass";
            $msg = "'make test' no errors";
        }
    }
    # Otherwise, get a result from Test::Harness output
    else {
        # figure out the right harness parser
        _expand_result( $result );
        my $harness_version = $result->{toolchain}{'Test::Harness'}{have};
        my $harness_parser = CPAN::Version->vgt($harness_version, '2.99_01')
                    ? \&_parse_tap_harness
                    : \&_parse_test_harness;
        # parse lines in reverse
        for my $i ( reverse 0 .. $#{$output} ) {
            if ( $output->[$i] =~ m{No support for OS|OS unsupported}ims ) { # from any *.t file
                $grade = 'na';
                $msg = 'This platform is not supported';
            }
            elsif ( $output->[$i] =~ m{^.?No tests defined}ms ) { # from M::B
                $grade = 'unknown';
                $msg = 'No tests provided';
            }
            else {
                ($grade, $msg) = $harness_parser->( $output->[$i] );
            }
            last if $grade;
        }
        # fallback on exit value if no recognizable Test::Harness output
        if ( ! $grade ) {
            $grade = $result->{exit_value} ? "fail" : "pass";
            $msg = ( $result->{is_make} ? "'make test' " : "'Build test' " )
                 . ( $result->{exit_value} ? "error detected" : "no errors");
        }
    }

    $result->{grade} = $grade;
    $result->{grade_msg} = $msg;

    _downgrade_known_causes( $result );

    $result->{success} =  $result->{grade} eq 'pass'
                       || $result->{grade} eq 'unknown';
    return;
}

#--------------------------------------------------------------------------#
# _dispatch_report
#
# Set up Test::Reporter and prompt user for edit, send
#--------------------------------------------------------------------------#

sub _dispatch_report {
    my $result = shift;
    my $phase = $result->{phase};

    $CPAN::Frontend->myprint(
        "CPAN::Reporter: preparing a CPAN Testers report for $result->{dist_name}\n"
    );

    # Get configuration options
    my $config_obj = CPAN::Reporter::Config::_open_config_file();
    my $config;
    $config = CPAN::Reporter::Config::_get_config_options( $config_obj )
        if $config_obj;
    if ( ! $config->{email_from} ) {
        $CPAN::Frontend->mywarn( << "EMAIL_REQUIRED");

CPAN::Reporter: required 'email_from' option missing an email address, so
test report will not be sent. See documentation for configuration details.

Even though CPAN Testers no longer uses email, this email address will
show up in the report and help identify the tester.  This is required
for compatibility with tools that process legacy reports for analysis.

EMAIL_REQUIRED
        return;
    }

    # Need to know if this is a duplicate
    my $is_duplicate = CPAN::Reporter::History::_is_duplicate( $result );

    # Abort if the distribution name is not formatted according to
    # CPAN Testers requirements: Dist-Name-version.suffix
    # Regex from CPAN-Testers should extract name, separator, version
    # and extension
    my @format_checks = $result->{dist_basename} =~
        m{(.+)([\-\_])(v?\d.*)(\.(?:tar\.(?:gz|bz2)|tgz|zip))$}i;
    ;
    if ( ! grep { length } @format_checks ) {
        $CPAN::Frontend->mywarn( << "END_BAD_DISTNAME");

CPAN::Reporter: the distribution name '$result->{dist_basename}' does not
appear to be packaged according to CPAN tester guidelines. Perhaps it is
not a normal CPAN distribution.

Test report will not be sent.

END_BAD_DISTNAME

        # record this as a discard, instead
        $result->{grade} = 'discard';
        CPAN::Reporter::History::_record_history( $result )
            if not $is_duplicate;
        return;
    }

    # Gather 'expensive' data for the report
    _expand_result( $result);

    # Skip if distribution name matches the send_skipfile
    if ( $config->{send_skipfile} && -r $config->{send_skipfile} ) {
        my $send_skipfile = IO::File->new( $config->{send_skipfile}, "r" );
        my $dist_id = $result->{dist}->pretty_id;
        while ( my $pattern = <$send_skipfile> ) {
            chomp($pattern);
            # ignore comments
            next if substr($pattern,0,1) eq '#';
            # if it doesn't match, continue with next pattern
            next if $dist_id !~ /$pattern/i;
            # if it matches, warn and return
            $CPAN::Frontend->myprint( << "END_SKIP_DIST" );
CPAN::Reporter: '$dist_id' matched against the send_skipfile.

Test report will not be sent.

END_SKIP_DIST

            return;
        }
    }

    # Setup the test report
    my $tr = Test::Reporter->new;
    $tr->grade( $result->{grade} );
    $tr->distribution( $result->{dist_name}  );
    # Older Test::Reporter doesn't support distfile, but we need it for
    # Metabase transport
    $tr->distfile( $result->{dist}->pretty_id )
      if $Test::Reporter::VERSION >= 1.54;

    # Skip if duplicate and not sending duplicates
    if ( $is_duplicate ) {
        if ( _prompt( $config, "send_duplicates", $tr->grade) =~ /^n/ ) {
            $CPAN::Frontend->myprint(<< "DUPLICATE_REPORT");

CPAN::Reporter: this appears to be a duplicate report for the $phase phase:
@{[$tr->subject]}

Test report will not be sent.

DUPLICATE_REPORT

            return;
        }
    }

    # Set debug and transport options, if supported
    $tr->debug( $config->{debug} ) if defined $config->{debug};
    my $transport = $config->{transport};
    unless ( defined $transport && length $transport ) {
        $CPAN::Frontend->mywarn( << "TRANSPORT_REQUIRED");

CPAN::Reporter: required 'transport' option missing so the test report
will not be sent. See documentation for configuration details.

TRANSPORT_REQUIRED
        return;
    }
    my @transport_args = split " ", $transport;

    # special hack for Metabase arguments
    if ($transport_args[0] eq 'Metabase') {
        @transport_args = _validate_metabase_args(@transport_args);
        unless (@transport_args) {
            $CPAN::Frontend->mywarn( "Test report will not be sent.\n\n" );
            return;
        }
    }

    eval { $tr->transport( @transport_args ) };
    if ($@) {
        $CPAN::Frontend->mywarn(
            "CPAN::Reporter: problem with Test::Reporter transport: \n" .
            "$@\n" .
            "Test report will not be sent\n"
        );
        return;
    }

    # prepare mail transport
    $tr->from( $config->{email_from} );

    # Populate the test report
    $tr->comments( _report_text( $result ) );
    $tr->via( 'CPAN::Reporter ' . $CPAN::Reporter::VERSION );

    # prompt for editing report
    if ( _prompt( $config, "edit_report", $tr->grade ) =~ /^y/ ) {
        my $editor = $config->{editor};
        local $ENV{VISUAL} = $editor if $editor; ## no critic
        $tr->edit_comments;
    }

    # send_*_report can override send_report
    my $send_config = defined $config->{"send_$phase\_report"}
                    ? "send_$phase\_report"
                    : "send_report" ;
    if ( _prompt( $config, $send_config, $tr->grade ) =~ /^y/ ) {
        $CPAN::Frontend->myprint( "CPAN::Reporter: sending test report with '" . $tr->grade .
              "' via " . $transport_args[0] . "\n");
        if ( $tr->send() ) {
            CPAN::Reporter::History::_record_history( $result )
                if not $is_duplicate;
        }
        else {
            $CPAN::Frontend->mywarn( "CPAN::Reporter: " . $tr->errstr . "\n");

            if ( $config->{retry_submission} ) {
                sleep(3);

                $CPAN::Frontend->mywarn( "CPAN::Reporter: second attempt\n");
                $tr->errstr('');

                if ( $tr->send() ) {
                    CPAN::Reporter::History::_record_history( $result )
                        if not $is_duplicate;
                }
                else {
                    $CPAN::Frontend->mywarn( "CPAN::Reporter: " . $tr->errstr . "\n");
                }
            }

        }
    }
    else {
        $CPAN::Frontend->myprint("CPAN::Reporter: test report will not be sent\n");
    }

    return;
}

sub _report_timeout {
    my $result = shift;
    if ($result->{exit_value} == 9) {
        my $config_obj = CPAN::Reporter::Config::_open_config_file();
        my $config;
        $config = CPAN::Reporter::Config::_get_config_options( $config_obj )
            if $config_obj;

        if ($config->{'_store_problems_in_dir'}) {
            my $distribution = $result->{dist}->base_id;
            my $file = "e9.$distribution.${\(time)}.$$.log";
            if (open my $to_log_fh, '>>', $config->{'_store_problems_in_dir'}.'/'.$file) {
                print $to_log_fh $distribution,"\n";
                print $to_log_fh "stage: ",$result->{phase},"\n";
                print $to_log_fh $Config{archname},"\n";
                print $to_log_fh _report_text( $result );
            } else {
                $CPAN::Frontend->mywarn( "CPAN::Reporter: writing ".
                    $config->{'_store_problems_in_dir'}.'/'.$file. " failed\n");
            }
        }
        if ($config->{'_problem_log'}) {
            my $distribution = $result->{dist}->base_id;
            if (open my $to_log_fh, '>>', $config->{'_problem_log'}) {
                print $to_log_fh "$result->{phase} $distribution $Config{archname}\n";
            } else {
                $CPAN::Frontend->mywarn( "CPAN::Reporter: writing ".
                    $config->{'_store_problems_in_dir'}. " failed\n");
            }
        }
    }
}

#--------------------------------------------------------------------------#
# _downgrade_known_causes
# Downgrade failure/unknown grade if we can determine a cause
# If platform not supported => 'na'
# If perl version is too low => 'na'
# If stated prereqs missing => 'discard'
#--------------------------------------------------------------------------#

sub _downgrade_known_causes {
    my ($result) = @_;
    my ($grade, $output) = ( $result->{grade}, $result->{output} );
    my $msg = $result->{grade_msg} || q{};

    # shortcut unless fail/unknown; but PL might look like pass but actually
    # have "OS Unsupported" messages if someone printed message and then
    # did "exit 0"
    return if $grade eq 'na';
    return if $grade eq 'pass' && $result->{phase} ne 'PL';

    # get prereqs
    _expand_result( $result );

    _report_timeout( $result );

    # if process was halted with a signal, just set for discard and return
    if ( $result->{exit_value} & 127 ) {
        $result->{grade} = 'discard';
        $result->{grade_msg} = 'Command interrupted';
        return;
    }

    # look for perl version error messages from various programs
    # "Error evaling..." type errors happen on Perl < 5.006 when modules
    # define their version with "our $VERSION = ..."
    my ($harness_error, $version_error, $unsupported) ;
    for my $line ( @$output ) {
      if ( $result->{phase} eq 'test'
        && $line =~ m{open3: IO::Pipe: Can't spawn.*?TAP/Parser/Iterator/Process.pm}
      ) {
        $harness_error++;
        last;
      }
      if( $line =~ /(?<!skipped: )Perl .*? required.*?--this is only/ims ||
           #?<! - quick hack for https://github.com/cpan-testers/CPAN-Reporter/issues/23
        $line =~ /Perl version .*? or higher required\. We run/ims || #EU::MM
        $line =~ /ERROR: perl: Version .*? is installed, but we need version/ims ||
        $line =~ /ERROR: perl \(.*?\) is installed, but we need version/ims ||
        $line =~ /Error evaling version line 'BEGIN/ims ||
        $line =~ /Could not eval '/ims
      ) {
        $version_error++;
        last;
      }
      if ( $line =~ /No support for OS|OS unsupported/ims ) {
        $unsupported++;
        last;
      }
    }

    # if the test harness had an error, discard the report
    if ( $harness_error ) {
      $grade = 'discard';
      $msg = 'Test harness failure';
    }
    # check for explicit version error or just a perl version prerequisite
    elsif ( $version_error || $result->{prereq_pm} =~ m{^\s+!\s+perl\s}ims ) {
        $grade = 'na';
        $msg = 'Perl version too low';
    }
    # check again for unsupported OS in case we took 'fail' from exit value
    elsif ( $unsupported  ) {
        $grade = 'na';
        $msg = 'This platform is not supported';
    }
    # check for Makefile without 'test' target; there are lots
    # of variations on the error message, e.g. "target test", "target 'test'",
    # "'test'", "`test'" and so on.
    elsif (
      $result->{is_make} && $result->{phase} eq 'test' && ! _has_test_target()
    ) {
        $grade = 'unknown';
        $msg = 'No make test target';
    }
    # check the prereq report for missing or failure flag '!'
    elsif ( $grade ne 'pass' && $result->{prereq_pm} =~ m{n/a}ims ) {
        $grade = 'discard';
        $msg = "Prerequisite missing:\n$result->{prereq_pm}";
    }
    elsif ( $grade ne 'pass' && $result->{prereq_pm} =~ m{^\s+!}ims ) {
        $grade = 'discard';
        $msg = "Prerequisite version too low:\n$result->{prereq_pm}";
    }
    # in PL stage -- if pass but no Makefile or Build, then this should
    # be recorded as a discard
    elsif ( $result->{phase} eq 'PL' && $grade eq 'pass'
         && ! -f 'Makefile' && ! -f 'Build'
    ) {
        $grade = 'discard';
        $msg = 'No Makefile or Build file found';
    }
    elsif ( $result->{command} =~ /Build.*?-j/ ) {
        $grade = 'discard';
        $msg = '-j is not a valid option for Module::Build (upgrade your CPAN.pm)';
    }
    elsif (
      $result->{is_make} && $result->{phase} eq 'make' &&
      grep { /Makefile out-of-date with respect to Makefile.PL/ } @$output
    ) {
        $grade = 'discard';
        $msg = 'Makefile out-of-date';
    }

    # store results
    $result->{grade} = $grade;
    $result->{grade_msg} = $msg;

    return;
}

#--------------------------------------------------------------------------#
# _expand_result - add expensive information like prerequisites and
# toolchain that should only be generated if a report will actually
# be sent
#--------------------------------------------------------------------------#

sub _expand_result {
    my $result = shift;
    return if $result->{expanded}++; # only do this once
    $result->{prereq_pm} = _prereq_report( $result->{dist} );
    {
      # mirror PERL5OPT as in record_command
      local $ENV{PERL5OPT} = _get_perl5opt() if _is_PL($result->{command});
      $result->{env_vars} = _env_report();
    }
    $result->{special_vars} = _special_vars_report();
    $result->{toolchain_versions} = _toolchain_report( $result );
    $result->{perl_version} = CPAN::Reporter::History::_format_perl_version();
    return;
}

#--------------------------------------------------------------------------#
# _env_report
#--------------------------------------------------------------------------#

# Entries bracketed with "/" are taken to be a regex; otherwise literal
my @env_vars= qw(
    /HARNESS/
    /LC_/
    /PERL/
    /_TEST/
    CCFLAGS
    COMSPEC
    INCLUDE
    INSTALL_BASE
    LANG
    LANGUAGE
    LD_LIBRARY_PATH
    LDFLAGS
    LIB
    NON_INTERACTIVE
    NUMBER_OF_PROCESSORS
    PATH
    PREFIX
    PROCESSOR_IDENTIFIER
    SHELL
    TERM
    TEMP
    TMPDIR
);

sub _env_report {
    my @vars_found;
    for my $var ( @env_vars ) {
        if ( $var =~ m{^/(.+)/$} ) {
            push @vars_found, grep { /$1/ } keys %ENV;
        }
        else {
            push @vars_found, $var if exists $ENV{$var};
        }
    }

    my $report = "";
    for my $var ( sort @vars_found ) {
        my $value = $ENV{$var};
        $value = '[undef]' if ! defined $value;
        $report .= "    $var = $value\n";
    }
    return $report;
}

#--------------------------------------------------------------------------#
# _file_copy_quiet
#
# manual file copy -- quietly return undef on failure
#--------------------------------------------------------------------------#

sub _file_copy_quiet {
  my ($source, $target) = @_;
  # ensure we have a target directory
  mkpath( dirname($target) ) or return;
  # read source
  local *FH;
  open FH, "<$source" or return; ## no critic
  my $pm_guts = do { local $/; <FH> };
  close FH;
  # write target
  open FH, ">$target" or return; ## no critic
  print FH $pm_guts;
  close FH;
  return 1;
}

#--------------------------------------------------------------------------#
# _get_perl5opt
#--------------------------------------------------------------------------#

sub _get_perl5opt {
  my $perl5opt = $ENV{PERL5OPT} || q{};
  if ( $Autoflush_Lib ) {
    $perl5opt .= q{ } if length $perl5opt;
    $perl5opt .= "-I$Autoflush_Lib " if $] >= 5.008;
    $perl5opt .= "-MDevel::Autoflush";
  }
  return $perl5opt;
}

#--------------------------------------------------------------------------#
# _has_recursive_make
#
# Ignore Makefile.PL in t directories
#--------------------------------------------------------------------------#

sub _has_recursive_make {
    my $PL_count = 0;
    File::Find::find(
        sub {
            if ( $_ eq 't' ) {
                $File::Find::prune = 1;
            }
            elsif ( $_ eq 'Makefile.PL' ) {
                $PL_count++;
            }
        },
        File::Spec->curdir()
    );
    return $PL_count > 1;
}

#--------------------------------------------------------------------------#
# _has_test_target
#--------------------------------------------------------------------------#

sub _has_test_target {
  my $fh = IO::File->new("Makefile") or return;
  return scalar grep { /^test[ ]*:/ } <$fh>;
}

#--------------------------------------------------------------------------#
# _init_result -- create and return a hash of values for use in
# report evaluation and dispatch
#
# takes same argument format as grade_*()
#--------------------------------------------------------------------------#

sub _init_result {
    my ($phase, $dist, $system_command, $output, $exit_value) = @_;

    unless ( defined $output && defined $exit_value ) {
        my $missing;
        if ( ! defined $output && ! defined $exit_value ) {
            $missing = "exit value and output"
        }
        elsif ( defined $output && !defined $exit_value ) {
            $missing =  "exit value"
        }
        else {
            $missing = "output";
        }
        $CPAN::Frontend->mywarn(
            "CPAN::Reporter: had errors capturing $missing. Tests abandoned"
        );
        return;
    }

    if ( $dist->pretty_id =~ m{\w+/Perl6/} ) {
        $CPAN::Frontend->mywarn(
            "CPAN::Reporter: Won't report a Perl6 distribution."
        );
        return;
    }

    my $result = {
        phase => $phase,
        dist => $dist,
        command => $system_command,
        is_make => _is_make( $system_command ),
        output => ref $output eq 'ARRAY' ? $output : [ split /\n/, $output ],
        exit_value => $exit_value,
        # Note: pretty_id is like "DAGOLDEN/CPAN-Reporter-0.40.tar.gz"
        dist_basename => basename($dist->pretty_id),
        dist_name => $dist->base_id,
    };

    # Used in messages to user
    $result->{PL_file} = $result->{is_make} ? "Makefile.PL" : "Build.PL";
    $result->{make_cmd} = $result->{is_make} ? $Config{make} : "Build";

    # CPAN might fail to find an author object for some strange dists
    my $author = $dist->author;
    $result->{author} = defined $author ? $author->fullname : "Author";
    $result->{author_id} = defined $author ? $author->id : "" ;

    return $result;
}

#--------------------------------------------------------------------------#
# _is_make
#--------------------------------------------------------------------------#

sub _is_make {
    my $command = shift;
    return $command =~ m{\b(?:\S*make|Makefile.PL)\b}ims ? 1 : 0;
}

#--------------------------------------------------------------------------#
# _is_PL
#--------------------------------------------------------------------------#

sub _is_PL {
  my $command = shift;
  return $command =~ m{\b(?:Makefile|Build)\.PL\b}ims ? 1 : 0;
}

#--------------------------------------------------------------------------#
# _max_length
#--------------------------------------------------------------------------#

sub _max_length {
    my ($first, @rest) = @_;
    my $max = length $first;
    for my $term ( @rest ) {
        $max = length $term if length $term > $max;
    }
    return $max;
}


#--------------------------------------------------------------------------#
# _parse_tap_harness
#
# As of Test::Harness 2.99_02, the final line is provided by TAP::Harness
# as "Result: STATUS" where STATUS is "PASS", "FAIL" or "NOTESTS"
#--------------------------------------------------------------------------#


sub _parse_tap_harness {
    my ($line) = @_;
    if ( $line =~ m{^Result:\s+([A-Z]+)} ) {
        if    ( $1 eq 'PASS' ) {
            return ('pass', 'All tests successful');
        }
        elsif ( $1 eq 'FAIL' ) {
            return ('fail', 'One or more tests failed');
        }
        elsif ( $1 eq 'NOTESTS' ) {
            return ('unknown', 'No tests were run');
        }
    }
    elsif ( $line =~ m{Bailout called\.\s+Further testing stopped}ms ) {
        return ( 'fail', 'Bailed out of tests');
    }
    elsif ( $line =~ m{FAILED--Further testing stopped}ms ) { # TAP::Harness 3.49+
        return ( 'fail', 'Bailed out of tests');
    }
    return;
}

#--------------------------------------------------------------------------#
# _parse_test_harness
#
# Output strings taken from Test::Harness::
# _show_results()  -- for versions < 2.57_03
# get_results()    -- for versions >= 2.57_03
#--------------------------------------------------------------------------#

sub _parse_test_harness {
    my ($line) = @_;
    if ( $line =~ m{^All tests successful}ms ) {
        return ( 'pass', 'All tests successful' );
    }
    elsif ( $line =~ m{^FAILED--no tests were run}ms ) {
        return ( 'unknown', 'No tests were run' );
    }
    elsif ( $line =~ m{^FAILED--.*--no output}ms ) {
        return ( 'unknown', 'No tests were run');
    }
    elsif ( $line =~ m{FAILED--Further testing stopped}ms ) {
        return ( 'fail', 'Bailed out of tests');
    }
    elsif ( $line =~ m{^Failed }ms ) {  # must be lowercase
        return ( 'fail', 'One or more tests failed');
    }
    else {
        return;
    }
}

#--------------------------------------------------------------------------#
# _prereq_report
#--------------------------------------------------------------------------#

my @prereq_sections = qw(
  requires build_requires configure_requires opt_requires opt_build_requires
);

sub _prereq_report {
    my $dist = shift;
    my (%need, %have, %prereq_met, $report);

    # Extract requires/build_requires from CPAN dist
    my $prereq_pm = $dist->prereq_pm;

    if ( ref $prereq_pm eq 'HASH' ) {
        # CPAN 1.94 returns hash with requires/build_requires # so no need to support old style
        foreach (values %$prereq_pm) {
          if (defined && ref ne 'HASH') {
             require Data::Dumper;
             warn "Data error detecting prerequisites. Please report it to CPAN::Reporter bug tracker:";
             warn Data::Dumper::Dumper($prereq_pm);
             die "Stopping";
          }
        }

        for my $sec ( @prereq_sections ) {
            $need{$sec} = $prereq_pm->{$sec} if keys %{ $prereq_pm->{$sec} };
        }
    }

    # Extract configure_requires from META.yml if it exists
    if ( $dist->{build_dir} && -d $dist->{build_dir} ) {
      my $meta_yml = File::Spec->catfile($dist->{build_dir}, 'META.yml');
      if ( -f $meta_yml ) {
        my @yaml = eval { Parse::CPAN::Meta::LoadFile($meta_yml) };
        if ( $@ ) {
          $CPAN::Frontend->mywarn(
            "CPAN::Reporter: error parsing META.yml\n"
          );
        }
        if (  ref $yaml[0] eq 'HASH' &&
              ref $yaml[0]{configure_requires} eq 'HASH'
        ) {
          $need{configure_requires} = $yaml[0]{configure_requires};
        }
      }
    }

    # see what prereqs are satisfied in subprocess
    for my $section ( @prereq_sections ) {
        next unless ref $need{$section} eq 'HASH';
        my @prereq_list = %{ $need{$section} };
        next unless @prereq_list;
        my $prereq_results = _version_finder( @prereq_list );
        for my $mod ( keys %{$prereq_results} ) {
            $have{$section}{$mod} = $prereq_results->{$mod}{have};
            $prereq_met{$section}{$mod} = $prereq_results->{$mod}{met};
        }
    }

    # find formatting widths
    my ($name_width, $need_width, $have_width) = (6, 4, 4);
    for my $section ( @prereq_sections ) {
        for my $module ( keys %{ $need{$section} } ) {
            my $name_length = length $module;
            my $need_length = length $need{$section}{$module};
            my $have_length = length $have{$section}{$module};
            $name_width = $name_length if $name_length > $name_width;
            $need_width = $need_length if $need_length > $need_width;
            $have_width = $have_length if $have_length > $have_width;
        }
    }

    my $format_str =
        "  \%1s \%-${name_width}s \%-${need_width}s \%-${have_width}s\n";

    # generate the report
    for my $section ( @prereq_sections ) {
      if ( keys %{ $need{$section} } ) {
        $report .= "$section:\n\n";
        $report .= sprintf( $format_str, " ", qw/Module Need Have/ );
        $report .= sprintf( $format_str, " ",
          "-" x $name_width,
          "-" x $need_width,
          "-" x $have_width );
        for my $module (sort {lc $a cmp lc $b} keys %{ $need{$section} } ) {
          my $need = $need{$section}{$module};
          my $have = $have{$section}{$module};
          my $bad = $prereq_met{$section}{$module} ? " " : "!";
          $report .=
          sprintf( $format_str, $bad, $module, $need, $have);
        }
        $report .= "\n";
      }
    }

    return $report || "    No requirements found\n";
}

#--------------------------------------------------------------------------#
# _print_grade_msg -
#--------------------------------------------------------------------------#

sub _print_grade_msg {
    my ($phase, $result) = @_;
    my ($grade, $msg) = ($result->{grade}, $result->{grade_msg});
    $CPAN::Frontend->myprint( "CPAN::Reporter: $phase result is '$grade'");
    $CPAN::Frontend->myprint(", $msg") if defined $msg && length $msg;
    $CPAN::Frontend->myprint(".\n");
    return;
}

#--------------------------------------------------------------------------#
# _prompt
#
# Note: always returns lowercase
#--------------------------------------------------------------------------#

sub _prompt {
    my ($config, $option, $grade, $extra) = @_;
    $extra ||= q{};

    my %spec = CPAN::Reporter::Config::_config_spec();

    my $dispatch = CPAN::Reporter::Config::_validate_grade_action_pair(
        $option, join(q{ }, "default:no", $config->{$option} || '')
    );
    my $action = $dispatch->{$grade} || $dispatch->{default};
    my $intro = $spec{$option}{prompt} . $extra . " (yes/no)";
    my $prompt;
    if     ( $action =~ m{^ask/yes}i ) {
        $prompt = CPAN::Shell::colorable_makemaker_prompt( $intro, "yes" );
    }
    elsif  ( $action =~ m{^ask(/no)?}i ) {
        $prompt = CPAN::Shell::colorable_makemaker_prompt( $intro, "no" );
    }
    else {
        $prompt = $action;
    }
    return lc $prompt;
}

#--------------------------------------------------------------------------#
# _report_text
#--------------------------------------------------------------------------#

my %intro_para = (
    'pass' => <<'HERE',
Thank you for uploading your work to CPAN.  Congratulations!
All tests were successful.
HERE

    'fail' => <<'HERE',
Thank you for uploading your work to CPAN.  However, there was a problem
testing your distribution.

If you think this report is invalid, please consult the CPAN Testers Wiki
for suggestions on how to avoid getting FAIL reports for missing library
or binary dependencies, unsupported operating systems, and so on:

http://wiki.cpantesters.org/wiki/CPANAuthorNotes
HERE

    'unknown' => <<'HERE',
Thank you for uploading your work to CPAN.  However, attempting to
test your distribution gave an inconclusive result.

This could be because your distribution had an error during the make/build
stage, did not define tests, tests could not be found, because your tests were
interrupted before they finished, or because the results of the tests could not
be parsed.  You may wish to consult the CPAN Testers Wiki:

http://wiki.cpantesters.org/wiki/CPANAuthorNotes
HERE

    'na' => <<'HERE',
Thank you for uploading your work to CPAN.  While attempting to build or test
this distribution, the distribution signaled that support is not available
either for this operating system or this version of Perl.  Nevertheless, any
diagnostic output produced is provided below for reference.  If this is not
what you expect, you may wish to consult the CPAN Testers Wiki:

http://wiki.cpantesters.org/wiki/CPANAuthorNotes
HERE

);

sub _comment_text {

    # We assemble the completed comment as a series of "parts" which
    # will get joined together
    my @comment_parts;

    # All automated testing gets a preamble
    if ($ENV{AUTOMATED_TESTING}) {
        push @comment_parts,
            "this report is from an automated smoke testing program\n"
            . "and was not reviewed by a human for accuracy"
    }

    # If a comment file is provided, read it and add it to the comment
    my $confdir = CPAN::Reporter::Config::_get_config_dir();
    my $comment_file = File::Spec->catfile($confdir, 'comment.txt');
    if ( -d $confdir && -f $comment_file && -r $comment_file ) {
        open my $fh, '<:encoding(UTF-8)', $comment_file or die($!);
        my $text;
        do {
            local $/ = undef; # No record (line) seperator on input
            defined( $text = <$fh> ) or die($!);
        };
        chomp($text);
        push @comment_parts, $text;
        close $fh;
    }

    # If we have an empty comment so far, add a default value
    if (scalar(@comment_parts) == 0) {
        push @comment_parts, 'none provided';
    }

    # Join the parts seperated by a blank line
    return join "\n\n", @comment_parts;
}

sub _report_text {
    my $data = shift;
    my $test_log = join(q{},@{$data->{output}});
    if ( length $test_log > MAX_OUTPUT_LENGTH ) {
        my $max_k = int(MAX_OUTPUT_LENGTH/1000) . "K";
        $test_log = substr( $test_log, 0, MAX_OUTPUT_LENGTH/2 ) . "\n\n"
	    . "[Output truncated because it exceeded $max_k]\n\n"
	    . substr( $test_log, -(MAX_OUTPUT_LENGTH/2) );
    }

    my $comment_body = _comment_text();

    # generate report
    my $output = << "ENDREPORT";
Dear $data->{author},

This is a computer-generated report for $data->{dist_name}
on perl $data->{perl_version}, created by CPAN-Reporter-$CPAN::Reporter::VERSION\.

$intro_para{ $data->{grade} }
Sections of this report:

    * Tester comments
    * Program output
    * Prerequisites
    * Environment and other context

------------------------------
TESTER COMMENTS
------------------------------

Additional comments from tester:

$comment_body

------------------------------
PROGRAM OUTPUT
------------------------------

Output from '$data->{command}':

$test_log
------------------------------
PREREQUISITES
------------------------------

Prerequisite modules loaded:

$data->{prereq_pm}
------------------------------
ENVIRONMENT AND OTHER CONTEXT
------------------------------

Environment variables:

$data->{env_vars}
Perl special variables (and OS-specific diagnostics, for MSWin32):

$data->{special_vars}
Perl module toolchain versions installed:

$data->{toolchain_versions}
ENDREPORT

    return $output;
}

#--------------------------------------------------------------------------#
# _special_vars_report
#--------------------------------------------------------------------------#

sub _special_vars_report {
    my $special_vars = << "HERE";
    \$^X = $^X
    \$UID/\$EUID = $< / $>
    \$GID = $(
    \$EGID = $)
HERE
    if ( $^O eq 'MSWin32' && eval "require Win32" ) { ## no critic
        my @getosversion = Win32::GetOSVersion();
        my $getosversion = join(", ", @getosversion);
        $special_vars .= "    Win32::GetOSName = " . Win32::GetOSName() . "\n";
        $special_vars .= "    Win32::GetOSVersion = $getosversion\n";
        $special_vars .= "    Win32::FsType = " . Win32::FsType() . "\n";
        $special_vars .= "    Win32::IsAdminUser = " . Win32::IsAdminUser() . "\n";
    }
    return $special_vars;
}

#--------------------------------------------------------------------------#
# _split_redirect
#--------------------------------------------------------------------------#

sub _split_redirect {
    my $command = shift;
    my ($cmd, $prefix) = ($command =~ m{\A(.+?)(\|.*)\z});
    if (defined $cmd) {
        return ($cmd, $prefix);
    }
    else { # didn't match a redirection
        return $command
    }
}

#--------------------------------------------------------------------------#
# _temp_filename -- stand-in for File::Temp for backwards compatibility
#
# takes an optional prefix, adds 8 random chars and returns
# an absolute pathname
#
# NOTE -- manual unlink required
#--------------------------------------------------------------------------#

# @CHARS from File::Temp
my @CHARS = (qw/ A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
                 a b c d e f g h i j k l m n o p q r s t u v w x y z
                 0 1 2 3 4 5 6 7 8 9 _
             /);

sub _temp_filename {
    my ($prefix) = @_;
    $prefix = q{} unless defined $prefix;
    $prefix .= $CHARS[ int( rand(@CHARS) ) ] for 0 .. 7;
    return File::Spec->catfile(File::Spec->tmpdir(), $prefix);
}

#--------------------------------------------------------------------------#
# _timeout_wrapper
# Timeout technique adapted from App::cpanminus (thank you Miyagawa!)
#--------------------------------------------------------------------------#

sub _timeout_wrapper {
    my ($cmd, $timeout) = @_;

    # protect shell quotes
    $cmd = quotemeta($cmd);

    my $wrapper = sprintf << 'HERE', $timeout, $cmd, $cmd;
use strict;
my ($pid, $exitcode);
eval {
    $pid = fork;
    if ($pid) {
        local $SIG{CHLD};
        local $SIG{ALRM} = sub {die 'Timeout'};
        alarm %s;
        my $wstat = waitpid $pid, 0;
        alarm 0;
        $exitcode = $wstat == -1 ? -1 : $?;
    } elsif ( $pid == 0 ) {
        setpgrp(0,0); # new process group
        exec "%s";
    }
    else {
      die "Cannot fork: $!\n" unless defined $pid;
    }
};
if ($pid && $@ =~ /Timeout/){
    kill -9 => $pid; # and send to our child's whole process group
    waitpid $pid, 0;
    $exitcode = 9; # force result to look like SIGKILL
}
elsif ($@) {
    die $@;
}
print "(%s exited with $exitcode)\n";
HERE
    return $wrapper;
}

#--------------------------------------------------------------------------#
# _timeout_wrapper_win32
#--------------------------------------------------------------------------#

sub _timeout_wrapper_win32 {
    my ($cmd, $timeout) = @_;

    $timeout ||= 0;  # just in case upstream doesn't guarantee it

    eval "use Win32::Job ();";
    if ($@) {
        $CPAN::Frontend->mywarn( << 'HERE' );
CPAN::Reporter: you need Win32::Job for inactivity_timeout support.
Continuing without timeout...
HERE
        return;
    }

    my ($program) = split " ", $cmd;
    if (! File::Spec->file_name_is_absolute( $program ) ) {
        my $exe = $program . ".exe";
        my ($path) = grep { -e File::Spec->catfile($_,$exe) }
                     split /$Config{path_sep}/, $ENV{PATH};
        if (! $path) {
            $CPAN::Frontend->mywarn( << "HERE" );
CPAN::Reporter: can't locate $exe in the PATH.
Continuing without timeout...
HERE
            return;
        }
        $program = File::Spec->catfile($path,$exe);
    }

    # protect shell quotes and other things
    $_ = quotemeta($_) for ($program, $cmd);

    my $wrapper = sprintf << 'HERE', $program, $cmd, $timeout;
use strict;
use Win32::Job;
my $executable = "%s";
my $cmd_line = "%s";
my $timeout = %s;

my $job = Win32::Job->new() or die $^E;
my $ppid = $job->spawn($executable, $cmd_line);
$job->run($timeout);
my $status = $job->status;
my $exitcode = $status->{$ppid}{exitcode};
if ( $exitcode == 293 ) {
    $exitcode = 9; # map Win32::Job kill (293) to SIGKILL (9)
}
elsif ( $exitcode & 255 ) {
    $exitcode = $exitcode << 8; # how perl expects it
}
print "($cmd_line exited with $exitcode)\n";
HERE
    return $wrapper;
}

#--------------------------------------------------------------------------#-
# _toolchain_report
#--------------------------------------------------------------------------#

my @toolchain_mods= qw(
    CPAN
    CPAN::Meta
    Cwd
    ExtUtils::CBuilder
    ExtUtils::Command
    ExtUtils::Install
    ExtUtils::MakeMaker
    ExtUtils::Manifest
    ExtUtils::ParseXS
    File::Spec
    JSON
    JSON::PP
    Module::Build
    Module::Signature
    Parse::CPAN::Meta
    Test::Harness
    Test::More
    Test2
    YAML
    YAML::Syck
    version
);

sub _toolchain_report {
    my ($result) = @_;

    my $installed = _version_finder( map { $_ => 0 } @toolchain_mods );
    $result->{toolchain} = $installed;

    my $mod_width = _max_length( keys %$installed );
    my $ver_width = _max_length(
        map { $installed->{$_}{have} } keys %$installed
    );

    my $format = "    \%-${mod_width}s \%-${ver_width}s\n";

    my $report = "";
    $report .= sprintf( $format, "Module", "Have" );
    $report .= sprintf( $format, "-" x $mod_width, "-" x $ver_width );

    for my $var ( sort keys %$installed ) {
        $report .= sprintf("    \%-${mod_width}s \%-${ver_width}s\n",
                            $var, $installed->{$var}{have} );
    }

    return $report;
}


#--------------------------------------------------------------------------#
# _validate_metabase_args
#
# This is a kludge to make metabase transport args a little less
# clunky for novice users
#--------------------------------------------------------------------------#

sub _validate_metabase_args {
    my @transport_args = @_;
    shift @transport_args; # drop leading 'Metabase'
    my (%args, $error);

    if ( @transport_args % 2 != 0 ) {
        $error = << "TRANSPORT_ARGS";

CPAN::Reporter: Metabase 'transport' option had odd number of
parameters in the config file. See documentation for proper
configuration format.

TRANSPORT_ARGS
    }
    else {
        %args = @transport_args;

        for my $key ( qw/uri id_file/ ) {
            if ( ! $args{$key} ) {
                $error = << "TRANSPORT_ARGS";

CPAN::Reporter: Metabase 'transport' option did not have
a '$key' parameter in the config file. See documentation for
proper configuration format.

TRANSPORT_ARGS
            }
        }
    }

    if ( $error ) {
        $CPAN::Frontend->mywarn( $error );
        return;
    }

    $args{id_file} = CPAN::Reporter::Config::_normalize_id_file( $args{id_file} );

    if ( ! -r $args{id_file} ) {
        $CPAN::Frontend->mywarn( <<"TRANSPORT_ARGS" );

CPAN::Reporter: Could not find Metabase transport 'id_file' parameter
located at '$args{id_file}'.
See documentation for proper configuration of the 'transport' setting.

TRANSPORT_ARGS
        return;
    }

    return ('Metabase', %args);
}


#--------------------------------------------------------------------------#
# _version_finder
#
# module => version pairs
#
# This is done via an external program to show installed versions exactly
# the way they would be found when test programs are run.  This means that
# any updates to PERL5LIB will be reflected in the results.
#
# File-finding logic taken from CPAN::Module::inst_file().  Logic to
# handle newer Module::Build prereq syntax is taken from
# CPAN::Distribution::unsat_prereq()
#
#--------------------------------------------------------------------------#

my $version_finder = $INC{'CPAN/Reporter/PrereqCheck.pm'};

sub _version_finder {
    my %prereqs = @_;

    my $perl = Probe::Perl->find_perl_interpreter();
    my @prereq_results;

    my $prereq_input = _temp_filename( 'CPAN-Reporter-PI-' );
    my $fh = IO::File->new( $prereq_input, "w" )
        or die "Could not create temporary '$prereq_input' for prereq analysis: $!";
    $fh->print( map { "$_ $prereqs{$_}\n" } keys %prereqs );
    $fh->close;

    my $prereq_result = capture { system( $perl, $version_finder, '<', $prereq_input ) };

    unlink $prereq_input;

    my %result;
    for my $line ( split "\n", $prereq_result ) {
        next unless length $line;
        my ($mod, $met, $have) = split " ", $line;
        unless ( defined($mod) && defined($met) && defined($have) ) {
            $CPAN::Frontend->mywarn(
                "Error parsing output from CPAN::Reporter::PrereqCheck:\n" .
                $line
            );
            next;
        }
        $result{$mod}{have} = $have;
        $result{$mod}{met} = $met;
    }
    return \%result;
}

1;

# ABSTRACT: Adds CPAN Testers reporting to CPAN.pm

__END__

=for Pod::Coverage
configure
grade_PL
grade_make
grade_test
record_command
test

=begin wikidoc

= SYNOPSIS

From the CPAN shell:

 cpan> install Task::CPAN::Reporter
 cpan> reload cpan
 cpan> o conf init test_report

Installing [Task::CPAN::Reporter] will pull in additional dependencies
that new CPAN Testers will need.

Advanced CPAN Testers with custom [Test::Reporter::Transport] setups
may wish to install only CPAN::Reporter, which has fewer dependencies.

= DESCRIPTION

The CPAN Testers project captures and analyzes detailed results from building
and testing CPAN distributions on multiple operating systems and multiple
versions of Perl.  This provides valuable feedback to module authors and
potential users to identify bugs or platform compatibility issues and improves
the overall quality and value of CPAN.

One way individuals can contribute is to send a report for each module that
they test or install.  CPAN::Reporter is an add-on for the CPAN.pm module to
send the results of building and testing modules to the CPAN Testers project.
Full support for CPAN::Reporter is available in CPAN.pm as of version 1.92.

= GETTING STARTED

== Installation

The first step in using CPAN::Reporter is to install it using whatever
version of CPAN.pm is already installed.  CPAN.pm will be upgraded as
a dependency if necessary.

 cpan> install CPAN::Reporter

If CPAN.pm was upgraded, it needs to be reloaded.

 cpan> reload cpan

== Configuration

If upgrading from a very old version of CPAN.pm, users may be prompted to renew
their configuration settings, including the 'test_report' option to enable
CPAN::Reporter.

If not prompted automatically, users should manually initialize CPAN::Reporter
support.  After enabling CPAN::Reporter, CPAN.pm will automatically continue
with interactive configuration of CPAN::Reporter options.

 cpan> o conf init test_report

Users will need to enter an email address in one of the following formats:

 johndoe@example.com
 John Doe <johndoe@example.com>
 "John Q. Public" <johnqpublic@example.com>

Users that are new to CPAN::Reporter should accept the recommended values
for other configuration options.

Users will be prompted to create a ~Metabase profile~ file that uniquely
identifies their test reports. See [/"The Metabase"] below for details.

After completing interactive configuration, be sure to commit (save) the CPAN
configuration changes.

 cpan> o conf commit

See [CPAN::Reporter::Config] for advanced configuration settings.

=== The Metabase

CPAN::Reporter sends test reports to a server known as the Metabase.  This
requires an active Internet connection and a profile file.  To create the
profile, users will need to run {metabase-profile} from a terminal window and
fill the information at the prompts. This will create a file called
{metabase_id.json} in the current directory. That file should be moved to the
{.cpanreporter} directory inside the user's home directory.

Users with an existing metabase profile file (e.g. from another machine),
should copy it into the {.cpanreporter} directory instead of creating
a new one.  Profile files may be located outside the {.cpanreporter}
directory by following instructions in [CPAN::Reporter::Config].

=== Default Test Comments

This module puts default text into the "TESTER COMMENTS" section, typically,
"none provided" if doing interactive testing, or, if doing smoke testing that
sets C<$ENV{AUTOMATED_TESTING}> to a true value, "this report is from an
automated smoke testing program and was not reviewed by a human for
accuracy."  If C<CPAN::Reporter> is configured to allow editing of the
report, this can be edited during submission.

If you wish to override the default comment, you can create a file named
C<comment.txt> in the configuration directory (typically {.cpanreporter}
under the user's home directory), with the default comment you would
like to appear.

Note that if your test is an automated smoke
test (C<$ENV{AUTOMATED_TESTING}> is set to a true value), the smoke
test notice ("this report is from an automated smoke testing program and
was not reviewed by a human for accuracy") is included along with a blank
line before your C<comment.txt>, so that it is always possible to
distinguish automated tests from non-automated tests that use this
module.

== Using CPAN::Reporter

Once CPAN::Reporter is enabled and configured, test or install modules with
CPAN.pm as usual.

For example, to test the File::Marker module:

 cpan> test File::Marker

If a distribution's tests fail, users will be prompted to edit the report to
add additional information that might help the author understand the failure.

= UNDERSTANDING TEST GRADES

CPAN::Reporter will assign one of the following grades to the report:

* {pass} -- distribution built and tested correctly
* {fail} --  distribution failed to test correctly
* {unknown} -- distribution failed to build, had no test suite or outcome was
inconclusive
* {na} --- distribution is not applicable to this platform and/or
version of Perl

In returning results of the test suite to CPAN.pm, "pass" and "unknown" are
considered successful attempts to "make test" or "Build test" and will not
prevent installation.  "fail" and "na" are considered to be failures and
CPAN.pm will not install unless forced.

An error from Makefile.PL/Build.PL or make/Build will also be graded as
"unknown" and a failure will be signaled to CPAN.pm.

If prerequisites specified in {Makefile.PL} or {Build.PL} are not available,
no report will be generated and a failure will be signaled to CPAN.pm.

= PRIVACY WARNING

CPAN::Reporter includes information in the test report about environment
variables and special Perl variables that could be affecting test results in
order to help module authors interpret the results of the tests.  This includes
information about paths, terminal, locale, user/group ID, installed toolchain
modules (e.g. ExtUtils::MakeMaker) and so on.

These have been intentionally limited to items that should not cause harmful
personal information to be revealed -- it does ~not~ include your entire
environment.  Nevertheless, please do not use CPAN::Reporter if you are
concerned about the disclosure of this information as part of your test report.

Users wishing to review this information may choose to edit the report
prior to sending it.

= BUGS

Using command_timeout on Linux may cause problems. See
[https://rt.cpan.org/Ticket/Display.html?id=62310]

Please report any bugs or feature using the CPAN Request Tracker.
Bugs can be submitted through the web interface at
[http://rt.cpan.org/Dist/Display.html?Queue=CPAN-Reporter]

When submitting a bug or request, please include a test-file or a patch to an
existing test-file that illustrates the bug or desired feature.

= SEE ALSO

Information about CPAN::Testers:

* [CPAN::Testers] -- overview of CPAN Testers architecture stack
* [http://www.cpantesters.org] -- project home with all reports
* [http://wiki.cpantesters.org] -- documentation and wiki

Additional Documentation:

* [CPAN::Reporter::Config] -- advanced configuration settings
* [CPAN::Reporter::FAQ] -- hints and tips

=end wikidoc

=cut

# vim: ts=4 sts=4 sw=4 et:
