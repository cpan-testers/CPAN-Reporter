#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use Config::Tiny;
use IO::CaptureOutput qw/capture/;
use File::Spec;
use File::Temp qw/tempdir/;
use File::Path qw/mkpath rmtree/;
use t::Frontend;

plan tests => 9;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $temp_home = File::Spec->catdir( File::Spec->tmpdir(), $$ );

my $old_home = File::Spec->rel2abs( $temp_home );
my $old_config_dir = File::Spec->catdir( $old_home, ".cpanreporter" );
my $old_config_file = File::Spec->catfile( $old_config_dir, "config.ini" );
my $new_home = $old_home . "-new";
my $new_config_dir = File::Spec->catdir( $new_home, ".cpanreporter" );
my $new_config_file = File::Spec->catfile( $new_config_dir, "config.ini" );

my ($rc, $stdout, $stderr);
my $email_line = "email_address = johndoe\@doe.org\n";

mkpath $old_config_dir;
open FILE, ">$old_config_file" or die $!;
print FILE $email_line;
close FILE;

#--------------------------------------------------------------------------#
# Mocking -- override support/system functions
#--------------------------------------------------------------------------#

BEGIN {
    $INC{"File/HomeDir.pm"} = 1; # fake load
}

package File::HomeDir;
our $VERSION = 999;
sub my_documents { return $old_home };
sub my_home { return $new_home };

package main;

#--------------------------------------------------------------------------#

# Make sure nothing happens when OS is not Darwin

{
    local $^O = 'unknown';
    require_ok('CPAN::Reporter::Config');
    ok( -d $old_config_dir,
        "non-darwin logic: old config dir still in place"
    );
    ok( ! -d $new_config_dir,
        "non-darwin logic: new config dir not created"
    );
}

# Reset %INC to get CPAN::Reporter to load again
delete $INC{'CPAN/Reporter/Config.pm'};
delete ${*CPAN::Reporter::Config}{$_} for ( keys %{*CPAN::Reporter::Config} );

{
    local $^O = 'darwin';
    capture sub {
        require_ok( "CPAN::Reporter::Config" );
    };
    ok( $INC{'CPAN/Reporter/Config.pm'},
        "CPAN::Reporter::Config reloaded"
    );
    ok( ! -d $old_config_dir,
        "darwin logic: old config-dir removed"
    );
    ok( -d $new_config_dir,
        "darwin logic: new config-dir created"
    );
    open CONFIG, "<$new_config_file" or die $!;
    is( scalar <CONFIG>, $email_line,
        "darwin logic: new config contents correct"
    );
    close CONFIG;
}

# cleanup

rmtree $new_home;
rmtree $old_home;

ok( ( ! -d $old_home) && ( ! -d $new_home ),
    "cleaned up temp directories"
);
