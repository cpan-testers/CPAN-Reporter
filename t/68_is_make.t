use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

use Test::More;
use t::Helper;
use t::Frontend;

my @cases = (
    # Makefile.PL based stuff should be true
    ['perl Makefile.PL' => 1],
    ['perl Makefile.PL LIBS=/foo' => 1],
    ['make' => 1],
    ['make LIBS=/foo' => 1],
    ['make test' => 1],
    ['make test TEST_VERBOSE=1' => 1],
    # make variants
    ['dmake' => 1],
    ['dmake LIBS=/foo' => 1],
    ['dmake test' => 1],
    ['dmake test TEST_VERBOSE=1' => 1],
    ['nmake' => 1],
    ['nmake LIBS=/foo' => 1],
    ['nmake test' => 1],
    ['nmake test TEST_VERBOSE=1' => 1],
    # Build.PL based stuff should be false
    ['perl Build.PL' => 0],
    ['perl Build.PL LIBS=/foo' => 0],
    ['Build' => 0],
    ['Build LIBS=/foo' => 0],
    ['Build test' => 0],
    ['Build test TEST_VERBOSE=1' => 0],
);

plan tests => 2 + @cases;

require_ok( 'CPAN::Reporter' );
can_ok( 'CPAN::Reporter', '_is_make' );

for my $c (@cases) {
    my ($cmd, $expected) = @$c;
    is( CPAN::Reporter::_is_make($cmd), $expected, $cmd );
}

