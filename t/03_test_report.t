#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use IO::Capture::Stdout;
use IO::Capture::Stderr;
use File::pushd qw/tempd/;
use File::Path qw/mkpath/;
use File::Spec;

#plan tests => 1;
plan 'no_plan';

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $temp_home = tempd; # deletes when out of scope, i.e. end of program

my $home_dir = File::Spec->rel2abs( $temp_home );
my $config_dir = File::Spec->catdir( $home_dir, ".cpanreporter" );
my $config_file = File::Spec->catfile( $config_dir, "config.ini" );
my $bogus_email = 'johndoe@nowhere.com';
my $bogus_smtp = 'mail.mail.com';

#--------------------------------------------------------------------------#
# Mocking -- override support/system functions
#--------------------------------------------------------------------------#
    
my $stdout = IO::Capture::Stdout->new;
my $stderr = IO::Capture::Stderr->new;

$INC{"File/HomeDir.pm"} = 1; # fake load
$INC{"Test/Reporter.pm"} = 1; # fake load

package File::HomeDir;
sub my_documents { return $home_dir };

package Test::Reporter;
sub new { return bless {}, 'Test::Reporter::Mocked' }

package Test::Reporter::Mocked;
sub AUTOLOAD { return 1 }

package main;

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
$tiny->{_}{smtp_server} = $bogus_smtp;
ok( $tiny->write( $config_file ),
    "created temp config file with a new email address and smtp server"
);

