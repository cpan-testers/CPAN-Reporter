# Bogus::Pass tests
use strict;

use Test::More;

plan tests =>  2 ;

fail( "Failed this test" );

# just spin and be interrupted by command_timeout
sleep 30;
die "Fail, fail, fail!";

pass( "Won't reach this test" );

