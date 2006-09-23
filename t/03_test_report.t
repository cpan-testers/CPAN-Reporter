#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;

use Config;
use File::pushd qw/pushd/;
use File::Path qw/mkpath/;
use File::Spec ();
use File::Temp qw/tempdir/;
use IO::CaptureOutput qw/capture/;
use Probe::Perl ();


my @test_distros = (
    # pass
    {
        name => 'Bogus-Pass',
        success => 1,
        grade => "pass",
    },
    # fail
    {
        name => 'Bogus-Fail',
        success => 0,
        grade => "fail",
    },
    {
        name => 'Bogus-NoTestOutput',
        success => 0,
        grade => "fail",
    },
    # unknown
    {
        name => 'Bogus-NoTests',
        success => 1,
        grade => "unknown"
    },
    # na -- TBD
);

plan tests => 4 + 5 * @test_distros;

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
sub AUTOLOAD { return 1 }

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
#   * make/dmake test -- pass, fail, unknown, na
#   * Build test -- pass, fail, unknown, na
#   * dmake and Build with test.pl -- aborts currently
#   * dmake and Build with bad prereqs
#--------------------------------------------------------------------------#

for my $case ( @test_distros ) {
    local $ENV{PERL_MM_USE_DEFAULT} = 1;
    
    my $wd = pushd( File::Spec->catdir( qw/t dist /, $case->{name} ) );
    my $dist = t::MockCPANDist->new( %mock_dist, pretty_id => "Bogus::Module" );
    
    my ($stdout, $stderr, $makefile_rc, $test_make_rc);
    
    pass "Testing $case->{name}";
    eval {
        capture sub {
            $makefile_rc = ! system("$perl Makefile.PL");
            $test_make_rc = CPAN::Reporter::test( $dist, "$make test" );
            system("$make realclean");
        }, \$stdout, \$stderr;
        return 1;
    } or diag "$@\n\nSTDOUT:\n$stdout\n\nSTDERR:\n$stderr\n";
     
    ok( $makefile_rc,
        "$case->{name}: Makefile.PL returned true"
    ); 
    ok( $case->{success} ? $test_make_rc : ! $test_make_rc, 
        "$case->{name}: test('make test') returned $case->{success}"
    ) or diag "STDOUT:\n$stdout\n\nSTDERR:\n$stderr"; 
    
    SKIP: {

        eval "require Module::Build";
        skip "Module::Build not installed", 2
            if $@;
        
        my ($build_rc, $test_build_rc);
        
        capture sub {
            $build_rc = ! system("$perl Build.PL");
            $test_build_rc = CPAN::Reporter::test( $dist, "$perl Build test" );
            system("$perl Build realclean");
        }, \$stdout, \$stderr;

        ok( $build_rc,
            "$case->{name}: Build.PL returned true"
        ); 
        ok( $case->{success} ? $test_build_rc : ! $test_build_rc, 
            "$case->{name}: test('perl Build test') returned $case->{success}"
        ) or diag "STDOUT:\n$stdout\n\nSTDERR:\n$stderr"; 
    }
    
} 
