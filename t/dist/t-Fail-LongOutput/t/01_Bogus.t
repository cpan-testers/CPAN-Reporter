# Bogus::Pass tests
use strict;

use Test::More;

plan tests =>  1 ;

fail( "Failed this test" );
diag "A" x 50 for ( 0 .. 2000 ); # 100K 

