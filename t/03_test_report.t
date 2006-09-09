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
use Probe::Perl ();


my %distro_pass = (
    'Bogus-Pass' => 1,
    'Bogus-Fail' => 0,
);

plan tests => 4 + 4 * keys %distro_pass;

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

for my $d ( keys %distro_pass ) {
    local $ENV{PERL_MM_USE_DEFAULT} = 1;
    my $pass = $distro_pass{$d};
    
    my $wd = pushd( File::Spec->catdir( qw/t dist /, $d ) );
    my $dist = t::MockCPANDist->new( %mock_dist, pretty_id => "Bogus::Pass" );
    
    local *OLDOUT;
    open( OLDOUT, ">&STDOUT" )
        or die "Couldn't save STDOUT before testing";

    open( STDOUT, ">$temp_stdout" )
        or die "Couldn't redirect STDOUT before testing";
    $|++;

    my $makefile_rc = ! system("$perl Makefile.PL");
    my $test_make_rc = CPAN::Reporter::test( $dist, "$make test" );
    system("$make realclean");
    
    my $build_rc = ! system("$perl Build.PL");
    my $test_build_rc = CPAN::Reporter::test( $dist, "$perl Build test" );
    system("$perl Build realclean");

    close(STDOUT); open(STDOUT, ">&OLDOUT");
    
    ok( $makefile_rc,
        "$d: Makefile.PL returned true"
    ); 
    ok( $pass ? $test_make_rc : ! $test_make_rc, 
        "$d: test('make test') returned $pass"
    ); 
    
    ok( $build_rc,
        "$d: Build.PL returned true"
    ); 
    ok( $pass ? $test_build_rc : ! $test_build_rc, 
        "$d: test('perl Build test') returned $pass"
    ); 
} 
