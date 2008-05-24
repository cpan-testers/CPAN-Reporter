use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

use Test::More;
use Config;
use File::Copy::Recursive qw/fcopy/;
use File::Path qw/mkpath/;
use File::Spec::Functions qw/catdir catfile rel2abs/;
use File::Temp qw/tempdir/;
use t::Frontend;
use t::MockHomeDir;

#plan 'no_plan';
plan tests => 21;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $config_dir = catdir( t::MockHomeDir::home_dir, ".cpanreporter" );
my $config_file = catfile( $config_dir, "config.ini" );

my $history_file = catfile( $config_dir, "reports-sent.db" );
my $sample_history_file = catfile(qw/t history reports-sent-longer.db/); 

my @fake_results = (
    { dist_name => 'Baz-Bam-3.14', phase => 'test',  grade => 'pass' },
    { dist_name => 'Foo-Bar-1.23', phase => 'PL',    grade => 'fail' },
    { dist_name => 'Foo-Bar-1.23', phase => 'test',  grade => 'fail' },
    { dist_name => 'Foo-Bar-1.23', phase => 'test',  grade => 'pass' },
    { dist_name => 'Wibble-42',    phase => 'test',  grade => 'pass' },
    { dist_name => 'Wobble-23',    phase => 'PL',    grade => 'na'   },
    { dist_name => 'Inline-0.44',  phase => 'test',  grade => 'pass' },
    { dist_name => 'Crappy-0.01',  phase => 'PL',    grade => 'discard' },
);

#--------------------------------------------------------------------------##
# begin testing
#--------------------------------------------------------------------------#
my @aoh;

mkpath( $config_dir );
ok( -d $config_dir, "temporary config dir created" );

# If old history exists, convert it
fcopy( $sample_history_file, $history_file);
ok( -f $history_file, "copied sample old history file to config directory");

# make it writeable
chmod 0644, $history_file;
ok( -w $history_file, "history file is writeable" );

# load CPAN::Reporter::History and import have_tested for convenience
require_ok( 'CPAN::Reporter::History' );
CPAN::Reporter::History->import( 'have_tested' );

# put in some data for current perl/arch/osname
CPAN::Reporter::History::_record_history($_) for @fake_results;

# one parameter should die
eval { have_tested( 'Wibble-42' ) };
ok ( $@, "have_tested() dies with odd number of arguments" );

# unknown parameter shoudl die
eval { have_tested( distname => 'Wibble-42' ) };
ok ( $@, "have_tested() dies with unknown parameter" );

# have_tested without any parameters should return everything on this platform
@aoh = have_tested();
is( scalar @aoh, scalar @fake_results, 
    "have_tested() with no args gives everything on this platform"
);

# have_tested a dist that was only tested once - return AoH with only one hash
@aoh = have_tested( dist => 'Wibble-42');

is( scalar @aoh, 1, 
    "asking for a unique dist"
);
is( ref $aoh[0], 'HASH',
    "returned an AoH"
);

is_deeply( $aoh[0], 
    {
        phase => 'test',
        grade => 'PASS',
        dist => 'Wibble-42', 
        perl => CPAN::Reporter::History::_format_perl_version(),
        archname => $Config{archname},
        osvers => $Config{osvers},
    },
    "hash fields as expected"
);

# just dist returns all reports for that dist on current platform
@aoh = have_tested( dist => 'Foo-Bar-1.23' );
is( scalar @aoh, 3, 
    "asking for multiple dist reports (only on this platform)"
);

# just dist doesn't return reports from other platforms
@aoh = have_tested( dist => 'ExtUtils-ParseXS-2.18' );
is( scalar @aoh, 0, 
    "asking for multiple dist reports (with none on this platform)"
);

# just phase returns all reports for that dist on current platform
@aoh = have_tested( phase => 'test' );
is( scalar @aoh, 5, 
    "asking for all test phase reports (defaults to this platform)"
);

# just grade returns all reports of that grade on current platform
@aoh = have_tested( grade => 'na' );
is( scalar @aoh, 1, 
    "asking for all na grade reports (defaults to this platform)"
);

# just grade returns all reports of that grade on current platform
@aoh = have_tested( grade => 'NA' );
is( scalar @aoh, 1, 
    "asking for all NA grade reports (defaults to this platform)"
);

# just grade returns all reports of that grade on current platform
@aoh = have_tested( grade => 'DISCARD' );
is( scalar @aoh, 1, 
    "asking for all DISCARD grade reports (defaults to this platform)"
);

# restrict to just a particular dist and phase
@aoh = have_tested( dist => 'Foo-Bar-1.23', phase => 'test' );
is( scalar @aoh, 2, 
    "asking for dist in test phase (defaults to this platform)"
);

# dist reports on any platform
@aoh = have_tested( 
    dist => 'Inline-0.44', perl => q{}, archname => q{}, osvers => q{} 
);
is( scalar @aoh, 2, 
    "asking for dist across any perl/archname/osvers"
);

# restrict to a platform
@aoh = have_tested( 
    archname => 'not-a-real-archname', perl => q{}, osvers => q{} 
);
is( scalar @aoh, 12, 
    "asking for all results from an archname"
);

# restrict to a perl
@aoh = have_tested( 
    perl => '9.10.0', archname => q{}, osvers => q{} 
);
is( scalar @aoh, 9, 
    "asking for all results from a perl version"
);

# restrict to an osver
@aoh = have_tested( 
    perl => q{}, archname => q{}, osvers => q{another-fake-version} 
);
is( scalar @aoh, 3, 
    "asking for all results from an OS version"
);




