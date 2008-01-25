# Bogus::Pass tests
use strict;

use Test::More;

plan tests =>  2 ;

fail( "Failed this test" );

while (1) { sleep 30; } # spin until killed by command_timeout

pass( "Won't reach this test" );

