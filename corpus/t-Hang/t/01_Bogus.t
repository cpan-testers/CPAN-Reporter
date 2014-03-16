# Bogus::Pass tests
use strict;

use Test::More;

plan tests =>  2 ;

pass( "Passed this test" );

# just spin and be interrupted by command_timeout
my $now = time; 1 while ( time - $now < 40 );

die "!!! TIMER DIDNT TIMEOUT -- SHOULDNT BE HERE !!!";

pass( "Won't reach this test" );

