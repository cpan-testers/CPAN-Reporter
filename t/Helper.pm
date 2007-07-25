package t::Helper;
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

use vars qw/@EXPORT/;
@EXPORT = qw/
    test_grade_PL test_grade_PL_plan
    test_grade_test test_grade_test_plan
    test_fake_config test_fake_config_plan
    test_report test_report_plan
    test_dispatch test_dispatch_plan
/;

use base 'Exporter';

use Config;
use File::Basename;
use File::Copy::Recursive qw/dircopy/;
use File::Path qw/mkpath/;
use File::pushd qw/pushd/;
use File::Spec ();
use File::Temp qw/tempdir/;
use IO::CaptureOutput qw/capture/;
use Probe::Perl ();
use Test::More;

my $perl = Probe::Perl->find_perl_interpreter();
my $make = $Config{make};

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $temp_stdout = File::Temp->new();
my $temp_home = tempdir(
        "CPAN-Reporter-testhome-XXXXXXXX", TMPDIR => 1, CLEANUP => 1
);
my $home_dir = File::Spec->rel2abs( $temp_home );
my $config_dir = File::Spec->catdir( $home_dir, ".cpanreporter" );
my $config_file = File::Spec->catfile( $config_dir, "config.ini" );

my $bogus_email_from = 'johndoe@example.com';
my $bogus_email_to = 'no_one@example.com';
my $bogus_smtp = 'mail.mail.com';

# used to capture from fixtures
use vars qw/$sent_report @cc_list/;

#--------------------------------------------------------------------------#
# test config file prep
#--------------------------------------------------------------------------#

sub test_fake_config_plan() { 3 }
sub test_fake_config {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my %overrides = @_;

    is( File::HomeDir::my_documents(), $home_dir,
        "home directory mocked"
    ); 
    mkpath $config_dir;
    ok( -d $config_dir,
        "config directory created"
    );

    my $tiny = Config::Tiny->new();
    $tiny->{_}{email_from} = $bogus_email_from;
    $tiny->{_}{email_to} = $bogus_email_to; # failsafe
    $tiny->{_}{smtp_server} = $bogus_smtp;
    $tiny->{_}{cc_author} = "yes";
    $tiny->{_}{send_report} = "yes";
    $tiny->{_}{send_duplicates} = "yes"; # tests often repeat same stuff
    for my $key ( keys %overrides ) {
        $tiny->{_}{$key} = $overrides{$key};
    }
    ok( $tiny->write( $config_file ),
        "created temp config file with a new email address and smtp server"
    );
}


#--------------------------------------------------------------------------#
# dist tests
#--------------------------------------------------------------------------#

sub test_grade_test_plan() { 1 + 6 * 2 }
sub test_grade_test {
    my ($case, $dist) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # simplify dist name
    $dist->{short_name} = basename($dist->pretty_id);
    $dist->{short_name} =~ s/(\.tar\.gz|\.tgz|\.zip)$//i;

    # automate CPAN::Reporter prompting
    local $ENV{PERL_MM_USE_DEFAULT} = 1;

    # clone dist directory -- avoids needing to cleanup source
    my $dist_dir = File::Spec->catdir( qw/t dist /, $case->{name} );
    my $work_dir = tempdir( 
        "CPAN-Reporter-testdist-XXXXXXXX", TMPDIR => 1, CLEANUP => 1
    );
    ok( dircopy($dist_dir, $work_dir),
        "Copying $case->{name} to temporary build directory"
    );

    my $pushd = pushd $work_dir;

    for my $tool ( qw/eumm mb/ ) {
        SKIP: {
            my ($tool_mod, $tool_PL, $tool_cmd );
            if ( $tool eq 'eumm' ) {
                ($tool_mod, $tool_PL, $tool_cmd ) = (
                    "ExtUtils::MakeMaker",
                    "Makefile.PL",
                    "$make test",
                );
            }
            else {
                ($tool_mod, $tool_PL, $tool_cmd ) = (
                    "Module::Build",
                    "Build.PL",
                    "$perl Build test",
                );
            }

            eval "require $tool_mod";
            skip "$tool_mod not installed", 6
                if $@;
            
            my ($stdout, $stderr, $build_rc, $test_build_rc);
            
            $t::Helper::sent_report = undef;
            @t::Helper::cc_list = ();

            capture sub {
                $build_rc = do $tool_PL;
                $test_build_rc = CPAN::Reporter::test( $dist, $tool_cmd )
            }, \$stdout, \$stderr;

            ok( $build_rc,
                "$case->{name}: $tool_PL returned true"
            ); 
            
            my $is_rc_correct = $case->{"$tool\_success"} 
                              ? $test_build_rc : ! $test_build_rc;

            ok( $is_rc_correct, 
                "$case->{name}: test('$tool_cmd') returned " . 
                $case->{"$tool\_success"}
            );
            
            my $is_grade_correct;
            # Special case if discarding
            if ( $case->{"$tool\_grade"} eq 'discard' ) {
                $is_grade_correct = 
                    $stdout =~ /Test results were not valid/ms;

                ok( $is_grade_correct,
                    "$case->{name}: test('$tool_cmd') prerequisites not satisifed"
                );
                    
                like( $stdout, 
                    "/Test results for $dist->{short_name} will be discarded/",
                    "$case->{name}: discard message correct"
                );

                ok( ! defined $t::Helper::sent_report,
                    "$case->{name}: test results discarded"
                );
            }
            else {
                my $case_grade = $case->{"$tool\_grade"};
                $is_grade_correct = 
                    $stdout =~ /^Test result is '$case_grade'/ms;
                ok( $is_grade_correct, 
                    "$case->{name}: test('$tool_cmd') grade reported as '$case_grade'"
                );
                
                like( $stdout, "/Preparing a CPAN Testers report for $dist->{short_name}/",
                    "$case->{name}: report notification correct"
                );

                if ( -r $config_file ) {
                    ok( defined $t::Helper::sent_report && length $t::Helper::sent_report,
                        "$case->{name}: test report was mock sent"
                    );
                }
                else {
                    ok( ! defined $t::Helper::sent_report,
                        "$case->{name}: test results not sent"
                    );
                }
            }
            
            my $case_msg = $case->{"$tool\_msg"};
            like( $stdout, "/$case_msg/",
                "$case->{name}: test('$tool_cmd') grade explanation correct"
            );

            diag "STDOUT:\n$stdout\n\nSTDERR:\n$stderr\n" 
                unless ( $is_rc_correct && $is_grade_correct );
        }
    }   
}

#--------------------------------------------------------------------------#
# PL testing
#--------------------------------------------------------------------------#

sub test_grade_PL_plan() { 1 + 5 * 2 } 
sub test_grade_PL {
    my ($case, $dist) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # simplify dist name
    $dist->{short_name} = basename($dist->pretty_id);
    $dist->{short_name} =~ s/(\.tar\.gz|\.tgz|\.zip)$//i;

    # automate CPAN::Reporter prompting
    local $ENV{PERL_MM_USE_DEFAULT} = 1;

    # clone dist directory -- avoids needing to cleanup source
    my $dist_dir = File::Spec->catdir( qw/t dist /, $case->{name} );
    my $work_dir = tempdir( 
        "CPAN-Reporter-testdist-XXXXXXXX", TMPDIR => 1, CLEANUP => 1
    );
    ok( dircopy($dist_dir, $work_dir),
        "Copying $case->{name} to temporary build directory"
    );

    my $pushd = pushd $work_dir;

    for my $tool ( qw/eumm mb/ ) {
        SKIP: {
            my ($tool_mod, $tool_PL, $tool_cmd );
            if ( $tool eq 'eumm' ) {
                ($tool_mod, $tool_PL, $tool_cmd ) = (
                    "ExtUtils::MakeMaker",
                    "Makefile.PL",
                    "$perl Makefile.PL",
                );
            }
            else {
                ($tool_mod, $tool_PL, $tool_cmd ) = (
                    "Module::Build",
                    "Build.PL",
                    "$perl Build.PL",
                );
            }

            eval "require $tool_mod";
            skip "$tool_mod not installed", 6
                if $@;
            
            my ($stdout, $stderr, $build_rc, $test_build_rc);
            
            $t::Helper::sent_report = undef;
            @t::Helper::cc_list = ();

            my ($output, $exit_value, $rc);
            capture sub {
                ($output, $exit_value) = 
                    CPAN::Reporter::record_command($tool_cmd);
                $rc = CPAN::Reporter::grade_PL(
                    $dist, $tool_cmd, $output, $exit_value
                );
            }, \$stdout, \$stderr;
            
            my $is_rc_correct = $case->{"$tool\_success"} 
                              ? $rc : $rc;

            ok( $is_rc_correct, 
                "$case->{name}: grade_PL() returned " . 
                $case->{"$tool\_success"}
            );
            
            my $case_grade = $case->{"$tool\_grade"};

            # correct grade identified?
            my $is_grade_correct = 
                $stdout =~ /^'$tool_PL' result is '$case_grade'/ms;
            ok( $is_grade_correct, 
                "$case->{name}: '$tool_cmd' grade identified as '$case_grade'"
            );

            if ( $case_grade =~ m{fail|unknown} ) {
                # report should have been sent
                like( $stdout, "/Preparing a CPAN Testers report for $dist->{short_name}/",
                    "$case->{name}: report notification correct"
                );
                ok( defined $t::Helper::sent_report && length $t::Helper::sent_report,
                    "$case->{name}: report was mock sent"
                );
                my $case_msg = $case->{"$tool\_msg"};
                like( $stdout, "/$case_msg/",
                    "$case->{name}: '$tool_cmd' grade explanation correct"
                );
            }
            else {
                # report shouldn't have been sent
                ok( ! defined $t::Helper::sent_report ,
                    "$case->{name}: no $tool_PL report was sent"
                );
                pass("(advance test count)") for (0 .. 1);
            }
            
            diag "STDOUT:\n$stdout\n\nSTDERR:\n$stderr\n" 
                unless ( $is_rc_correct && $is_grade_correct );
        }
    }   

}

#--------------------------------------------------------------------------#
# report tests
#--------------------------------------------------------------------------#

my %report_para = (
    'pass' => <<'HERE',
Thank you for uploading your work to CPAN.  Congratulations!
All tests were successful.
HERE

    'fail' => <<'HERE',
Thank you for uploading your work to CPAN.  However, it appears that
there were some problems testing your distribution.
HERE

    'unknown' => << 'HERE',
Thank you for uploading your work to CPAN.  However, attempting to
test your distribution gave an inconclusive result.  This could be because
you did not define tests (or tests could not be found), because
your tests were interrupted before they finished, or because
the results of the tests could not be parsed by CPAN::Reporter.
HERE

    'na' => << 'HERE',
Thank you for uploading your work to CPAN.  While attempting to test this
distribution, the distribution signaled that support is not available either
for this operating system or this version of Perl.  Nevertheless, any 
diagnostic output produced is provided below for reference.
HERE
    
);

sub test_report_plan() { 10 };
sub test_report {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ($result) = @_;
    my $label = $result->{label};
    my $expected_grade = $result->{expected_grade};

    my ($stdout, $stderr, $err) = _run_report( $result );
    
    is( $err, q{}, 
        "report for $label ran without error" 
    );

    is( $result->{grade}, $expected_grade,
        "result graded correctly"
    );

    my $msg_re = $report_para{ $expected_grade };
    ok( defined $msg_re && length $msg_re,
        "$expected_grade grade paragraph selected for $label"
    );
    
    my $prereq = CPAN::Reporter::_prereq_report( $result->{dist} );
    # set PERL_MM_USE_DEFAULT to mirror _run_report
    local $ENV{PERL_MM_USE_DEFAULT} = 1;
    my $env_vars = CPAN::Reporter::_env_report();
    my $special_vars = CPAN::Reporter::_special_vars_report();
    my $toolchain_versions = CPAN::Reporter::_toolchain_report();
    
    like( $t::Helper::sent_report, '/' . quotemeta($msg_re) . '/ms',
        "correct intro paragraph for $label"
    );

    like( $t::Helper::sent_report, '/' . quotemeta($prereq) . '/ms',
        "prereq report found for $label"
    );
    
    like( $t::Helper::sent_report, '/' . quotemeta($env_vars) . '/ms',
        "environment variables found for $label"
    );
    
    like( $t::Helper::sent_report, '/' . quotemeta($special_vars) . '/ms',
        "special variables found for $label"
    );
    
    like( $t::Helper::sent_report, '/' . quotemeta($toolchain_versions) . '/ms',
        "toolchain versions found for $label"
    );
    
    like( $t::Helper::sent_report, '/' . quotemeta($result->{original}) . '/ms',
        "test output found for $label"
    );

    my @expected_cc;
    my $author = $result->{dist}->author;
    push @expected_cc, $author->id if defined $author;
    is_deeply( 
        [ @t::Helper::cc_list ], 
        [ map { $_ . '@cpan.org' } @expected_cc ],
        "cc list correct"
    );
};

#--------------------------------------------------------------------------#
# test_dispatch
#--------------------------------------------------------------------------#

sub test_dispatch_plan { 3 };
sub test_dispatch {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $result = shift;
    my %opt = @_;

    my ($stdout, $stderr, $err) = _run_report( $result );

    is( $err, q{}, 
            "generate report for $result->{label}" 
    );

    if ( $opt{will_send} ) {
        ok( defined $t::Helper::sent_report && length $t::Helper::sent_report,
            "report was sent for $result->{label}"
        );
        like( $stdout, "/Sending test report with/",
            "saw report sent message for $result->{label}"
        );
    }
    else {
        ok( ! defined $t::Helper::sent_report,
            "report not sent for $result->{label}"
        );
        like( $stdout, "/report will not be sent/",
            "saw report not sent message for $result->{label}"
        );
    }

}

#--------------------------------------------------------------------------#
# _run_report
#--------------------------------------------------------------------------#

sub _run_report {
    my $result = shift;

    # automate CPAN::Reporter prompting
    local $ENV{PERL_MM_USE_DEFAULT} = 1;
    
    my ($stdout, $stderr);
    
    $t::Helper::sent_report = undef;
    @t::Helper::cc_list = ();

    eval {
        capture sub {
            CPAN::Reporter::_expand_report( $result ); 
            CPAN::Reporter::_dispatch_report( $result );
        } => \$stdout, \$stderr;
        return 1;
    }; 

    return ($stdout, $stderr, $@);
}

#--------------------------------------------------------------------------#
# Mocking
#--------------------------------------------------------------------------#

BEGIN {
    $INC{"File/HomeDir.pm"} = 1; # fake load
    $INC{"Test/Reporter.pm"} = 1; # fake load
}

package File::HomeDir;
sub my_documents { return $home_dir };
sub my_home { return $home_dir };
sub my_data { return $home_dir };

package Test::Reporter;
sub new { print shift, "\n"; return bless {}, 'Test::Reporter::Mocked' }

package Test::Reporter::Mocked;
use Config;
use vars qw/$AUTOLOAD/;

sub comments { shift; $t::Helper::sent_report = shift }

sub send { shift; @t::Helper::cc_list = ( @_ ); return 1 } 

sub subject {
    my $self = shift;
    return uc($self->grade) . ' ' . $self->distribution .
        " $Config{archname} $Config{osvers}";
}

sub AUTOLOAD {
    my $self = shift;
    if ( @_ ) {
        $self->{ $AUTOLOAD } = shift;
    }
    return $self->{ $AUTOLOAD };
}


1;
