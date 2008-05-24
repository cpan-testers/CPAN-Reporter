use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

use Test::More;
use Config::Tiny;
use IO::CaptureOutput qw/capture/;
use File::Basename qw/basename/;
use File::Spec;
use File::Temp qw/tempdir/;
use t::Frontend;
use t::MockHomeDir;

plan tests => 10;
#plan 'no_plan';

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

# File::HomeDir will be mocked to return these
my $default_home_dir = t::MockHomeDir::home_dir;
my $default_config_dir = File::Spec->catdir( $default_home_dir, ".cpanreporter" );
my $default_config_file = File::Spec->catfile( $default_config_dir, "config.ini" );

# These will be tested via ENV vars
my $alt_home = tempdir( 
    "CPAN-Reporter-testhome-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 
) or die "Couldn't create a temporary config directory: $!\nIs your temp drive full?";
my $alt_home_dir = File::Spec->rel2abs( $alt_home );
my $alt_config_dir = File::Spec->catdir( $alt_home_dir, ".cpanreporter" );
my $alt_config_file = File::Spec->catfile( $alt_config_dir, "config.ini" );

# Secondary config files to check setting config file but config dir
my $default_dir_alt_file = File::Spec->catfile( $default_config_dir, "altconfig.ini" );
my $alt_dir_alt_file = File::Spec->catfile( $alt_config_dir, "altconfig.ini" );

#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');
require_ok('CPAN::Reporter::Config');

is( CPAN::Reporter::Config::_get_config_dir(), $default_config_dir,
    "default config dir path"
);
is( CPAN::Reporter::Config::_get_config_file(), $default_config_file,
    "default config file path"
);

# override config file
{
    local $ENV{PERL_CPAN_REPORTER_CONFIG} = $default_dir_alt_file;

    is( CPAN::Reporter::Config::_get_config_dir(), $default_config_dir,
        "PERL_CPAN_REPORTER_CONFIG: default config dir path"
    );
    is( CPAN::Reporter::Config::_get_config_file(), $default_dir_alt_file,
        "PERL_CPAN_REPORTER_CONFIG: alt config file path"
    );
}

# override config dir
{
    local $ENV{PERL_CPAN_REPORTER_DIR} = $alt_config_dir;

    is( CPAN::Reporter::Config::_get_config_dir(), $alt_config_dir,
        "PERL_CPAN_REPORTER_DIR: default config dir path"
    );
    is( CPAN::Reporter::Config::_get_config_file(), $alt_config_file,
        "PERL_CPAN_REPORTER_DIR: alt config file path"
    );
}

# override config dir and config file
{
    local $ENV{PERL_CPAN_REPORTER_DIR} = $alt_config_dir;
    local $ENV{PERL_CPAN_REPORTER_CONFIG} = $alt_dir_alt_file;

    is( CPAN::Reporter::Config::_get_config_dir(), $alt_config_dir,
        "DIR + CONFIG: alt config dir path"
    );
    is( CPAN::Reporter::Config::_get_config_file(), $alt_dir_alt_file,
        "DIR + CONFIG: alt config file path"
    );
}


