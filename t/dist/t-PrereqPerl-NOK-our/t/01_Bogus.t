# Bogus::Pass tests
use strict;

use Test::More;

plan tests =>  1 ;

die "Future Perl not invented yet" if $] < 42;

pass( "Passed this test" );
