package t::Helper;
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

use vars qw/@EXPORT/;
@EXPORT = qw/
    test_dist test_dist_plan
    test_fake_config test_fake_config_plan
    test_process_report test_process_report_plan
/;

use base 'Exporter';

use Config;
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

my $bogus_email = 'johndoe@nowhere.com';
my $bogus_smtp = 'mail.mail.com';

my $sent_report;

#--------------------------------------------------------------------------#
# test config file prep
#--------------------------------------------------------------------------#

sub test_fake_config_plan() { 3 }
sub test_fake_config {
    is( File::HomeDir::my_documents(), $home_dir,
        "home directory mocked"
    ); 
    mkpath $config_dir;
    ok( -d $config_dir,
        "config directory created"
    );

    my $tiny = Config::Tiny->new();
    $tiny->{_}{email_from} = $bogus_email;
    $tiny->{_}{email_to} = 'no_one@nowhere.com'; # failsafe
    $tiny->{_}{smtp_server} = $bogus_smtp;
    ok( $tiny->write( $config_file ),
        "created temp config file with a new email address and smtp server"
    );
}


#--------------------------------------------------------------------------#
# dist tests
#--------------------------------------------------------------------------#

sub test_dist_plan() { 9 }
sub test_dist {
    my ($case, $dist) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

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

    my ($stdout, $stderr, $makefile_rc, $test_make_rc);
    
    eval {
        capture sub {
            # Have to run Makefile separate as return value isn't reliable
            $makefile_rc = ! system("$perl Makefile.PL");
            $test_make_rc = CPAN::Reporter::test( $dist, "$make test" );
        }, \$stdout, \$stderr;
        return 1;
    } or diag "$@\n\nSTDOUT:\n$stdout\n\nSTDERR:\n$stderr\n";
     
    ok( $makefile_rc,
        "$case->{name}: Makefile.PL ran without error"
    ); 

    my $is_rc_correct = $case->{eumm_success} ? $test_make_rc : ! $test_make_rc;
    my $is_grade_correct = $stdout =~ /^Test result is '$case->{eumm_grade}'/ms;

    ok( $is_rc_correct, 
        "$case->{name}: test('make test') returned $case->{eumm_success}"
    );
        
    ok( $is_grade_correct, 
        "$case->{name}: test('make test') grade reported as '$case->{eumm_grade}'"
    );
        
    like( $stdout, "/$case->{eumm_msg}/",
        "$case->{name}: test('make test') grade explanation correct"
    );

    diag "STDOUT:\n$stdout\n\nSTDERR:\n$stderr\n" 
        unless ( $is_rc_correct && $is_grade_correct );
    
    SKIP: {

        eval "require Module::Build";
        skip "Module::Build not installed", 4
            if $@;
        
        my ($build_rc, $test_build_rc);
        
        capture sub {
            $build_rc = do "Build.PL";
            $test_build_rc = CPAN::Reporter::test( $dist, "$perl Build test" );
        }, \$stdout, \$stderr;

        ok( $build_rc,
            "$case->{name}: Build.PL returned true"
        ); 
        
        $is_rc_correct = $case->{mb_success} ? $test_build_rc : ! $test_build_rc;
        $is_grade_correct = $stdout =~ /^Test result is '$case->{mb_grade}'/ms;

        ok( $is_rc_correct, 
            "$case->{name}: test('perl Build test') returned $case->{mb_success}"
        );
            
        ok( $is_grade_correct, 
            "$case->{name}: test('perl Build test') grade reported as '$case->{mb_grade}'"
        );
        
        like( $stdout, "/$case->{mb_msg}/",
            "$case->{name}: test('perl Build test') grade explanation correct"
        );

        diag "STDOUT:\n$stdout\n\nSTDERR:\n$stderr\n" 
            unless ( $is_rc_correct && $is_grade_correct );
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
Thank you for uploading your work to CPAN.  However, it appears that
your distribution tests are not fully supported on this machine, either 
due to operating system limitations or missing prerequisite modules.
HERE
    
);

sub test_process_report_plan() { 9 };
sub test_process_report {
    my ($result) = @_;
    my $label = $result->{label};

    # automate CPAN::Reporter prompting
    local $ENV{PERL_MM_USE_DEFAULT} = 1;
    
    my ($stdout, $stderr);
    
    eval {
        capture sub {
            CPAN::Reporter::_process_report( $result ); 
        }, \$stdout, \$stderr;
        return 1;
    }; 
     
    is( $@, q{}, 
        "_process_report for $label" 
    );

    is( $result->{grade}, $label,
        "result graded correctly"
    );

    my $msg_re = $report_para{ $label };
    ok( defined $msg_re && length $msg_re,
        "grade paragraph selected for $label"
    );
    
    my $prereq = CPAN::Reporter::_prereq_report( $result->{dist} );
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
};

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

sub comments { shift; $t::Helper::sent_report = shift }

sub AUTOLOAD { return "1 mocked answer" }

1;
