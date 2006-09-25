#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;

use Config;
use File::Copy::Recursive qw/dircopy/;
use File::Path qw/mkpath/;
use File::pushd qw/pushd/;
use File::Spec ();
use File::Temp qw/tempdir/;
use IO::CaptureOutput qw/capture/;
use Probe::Perl ();


my @test_distros = (
    # pass
    {
        name => 'Bogus-Pass',
        eumm_success => 1,
        eumm_grade => "pass",
        mb_success => 1,
        mb_grade => "pass",
    },
    {
        name => 'Bogus-Test.pl-Pass',
        eumm_success => 1,
        eumm_grade => "pass",
        mb_success => 1,
        mb_grade => "pass",
    },
    # split pass/fail
    {
        name => 'Bogus-Test.pl-NoOutPass',
        eumm_success => 1,
        eumm_grade => "pass",
        mb_success => 0,
        mb_grade => "fail",
    },
    # fail
    {
        name => 'Bogus-Fail',
        eumm_success => 0,
        eumm_grade => "fail",
        mb_success => 0,
        mb_grade => "fail",
    },
    {
        name => 'Bogus-Test.pl-NoOutFail',
        eumm_success => 0,
        eumm_grade => "fail",
        mb_success => 0,
        mb_grade => "fail",
    },
    {
        name => 'Bogus-Test.pl-Fail',
        eumm_success => 0,
        eumm_grade => "fail",
        mb_success => 0,
        mb_grade => "fail",
    },
    {
        name => 'Bogus-NoTestOutput',
        eumm_success => 0,
        eumm_grade => "fail",
        mb_success => 0,
        mb_grade => "fail",
    },
    # unknown
    {
        name => 'Bogus-NoTestDir',
        eumm_success => 1,
        eumm_grade => "unknown",
        mb_success => 1,
        mb_grade => "unknown",
    },
    {
        name => 'Bogus-NoTestFiles',
        eumm_success => 1,
        eumm_grade => "unknown",
        mb_success => 1,
        mb_grade => "unknown",
    },
    # na -- TBD
);

plan tests => 4 + 7 * @test_distros;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $perl = Probe::Perl->find_perl_interpreter();
my $make = $Config{make};
my $temp_stdout = File::Temp->new();
my $temp_home = tempdir();
my $home_dir = File::Spec->rel2abs( $temp_home );
my $config_dir = File::Spec->catdir( $home_dir, ".cpanreporter" );
my $config_file = File::Spec->catfile( $config_dir, "config.ini" );


my $bogus_email = 'johndoe@nowhere.com';
my $bogus_smtp = 'mail.mail.com';
my %mock_dist = (
    prereq_pm       => {
        'File::Spec' => 0,
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

#--------------------------------------------------------------------------#
# Mocking -- override support/system functions
#--------------------------------------------------------------------------#
    
BEGIN {
    $INC{"File/HomeDir.pm"} = 1; # fake load
    $INC{"Test/Reporter.pm"} = 1; # fake load
}

package File::HomeDir;
sub my_documents { return $home_dir };

package Test::Reporter;
sub new { print shift, "\n"; return bless {}, 'Test::Reporter::Mocked' }

package Test::Reporter::Mocked;
sub AUTOLOAD { return "1 mocked answer" }

package main;

#--------------------------------------------------------------------------#
# test config file prep
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');
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

#--------------------------------------------------------------------------#
# Scenarios to test
#   * make/dmake test --  na
#   * Build test --  na
#   * dmake and Build with test.pl -- aborts currently
#   * dmake and Build with bad prereqs
#--------------------------------------------------------------------------#

for my $case ( @test_distros ) {
    # automate CPAN::Reporter prompting
    local $ENV{PERL_MM_USE_DEFAULT} = 1;

    # clone dist directory -- avoids needing to cleanup source
    my $dist_dir = File::Spec->catdir( qw/t dist /, $case->{name} );
    my $work_dir = tempdir();
    ok( dircopy($dist_dir, $work_dir),
        "Copying $case->{name} to temporary build directory"
    );

    my $pushd = pushd $work_dir;

    my $dist = t::MockCPANDist->new( %mock_dist, pretty_id => "Bogus::Module" );
    
    my ($stdout, $stderr, $makefile_rc, $test_make_rc);
    
    eval {
        capture sub {
            $makefile_rc = do "Makefile.PL";
            $test_make_rc = CPAN::Reporter::test( $dist, "$make test" );
        }, \$stdout, \$stderr;
        return 1;
    } or diag "$@\n\nSTDOUT:\n$stdout\n\nSTDERR:\n$stderr\n";
     
    ok( $makefile_rc,
        "$case->{name}: Makefile.PL returned true"
    ); 

    my $is_rc_correct = $case->{eumm_success} ? $test_make_rc : ! $test_make_rc;
    my $is_grade_correct = $stdout =~ /^Test result is '$case->{eumm_grade}'/ms;

    ok( $is_rc_correct, 
        "$case->{name}: test('make test') returned $case->{eumm_success}"
    );
        
    ok( $is_grade_correct, 
        "$case->{name}: test('make test') grade reported as '$case->{eumm_grade}'"
    );
        
    diag "STDOUT:\n$stdout\n\nSTDERR:\n$stderr\n" 
        unless ( $is_rc_correct && $is_grade_correct );
    
    SKIP: {

        eval "require Module::Build";
        skip "Module::Build not installed", 2
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
        
        diag "STDOUT:\n$stdout\n\nSTDERR:\n$stderr\n" 
            unless ( $is_rc_correct && $is_grade_correct );
    }
    
} 
