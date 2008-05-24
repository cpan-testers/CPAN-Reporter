use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use Config::Tiny;
use IO::CaptureOutput qw/capture/;
use File::Copy::Recursive qw/fcopy/;
use File::Path qw/mkpath/;
use File::Spec::Functions qw/catdir catfile rel2abs/;
use File::Temp qw/tempdir/;
use t::Frontend;
use t::MockHomeDir;

#plan 'no_plan';
plan tests => 12;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#


my $config_dir = catdir( t::MockHomeDir::home_dir, ".cpanreporter" );
my $config_file = catfile( $config_dir, "config.ini" );

my $old_history_file = catfile( $config_dir, "history.db" );
my $new_history_file = catfile( $config_dir, "reports-sent.db" );

my $sample_old_file = catfile(qw/t history history.db/); 
my $sample_new_file = catfile(qw/t history reports-sent.db/); 

my ($rc, $stdout, $stderr);

#--------------------------------------------------------------------------#

sub re_require {
    delete $INC{'CPAN/Reporter/History.pm'};
    eval {
        capture sub {
            require_ok( "CPAN::Reporter::History" );
        } => \$stdout, \$stderr;
    };
    die $@ if $@;
    return 1;
}

sub mtime {
    return (stat shift)[9];
}

sub read_file {
    my $fh = IO::File->new(shift);
    local $/;
    return scalar <$fh>;
}

#--------------------------------------------------------------------------##
# begin testing
#--------------------------------------------------------------------------#

mkpath( $config_dir );
ok( -d $config_dir, "temporary config dir created" );
ok( ! -f $old_history_file && ! -f $new_history_file, "no history files yet");

# Nothing should be created if nothing exists
re_require();
ok( ! -f $old_history_file && ! -f $new_history_file, "still no history files");

# If old history exists, convert it
fcopy( $sample_old_file, $old_history_file);
ok( -f $old_history_file, "copied sample old history file to config directory");
re_require();
like( $stdout, "/Upgrading automatically/", "saw upgrading notice" );
ok( -f $old_history_file, "old history file still exists" );
ok( -f $new_history_file, "new history file was created" );

my $expected_file = scalar read_file($sample_new_file);
$expected_file =~ s/VERSION/$CPAN::Reporter::History::VERSION/;
is( scalar read_file($new_history_file), $expected_file,
    "new history contents as expected"
);

# If new history exists, leave it alone
my $mtime = mtime( $new_history_file );
sleep(2); # ensure mtime check works
re_require();
is( mtime($new_history_file), $mtime, "new history file unmodified" );

