# Bogus::Pass tests
use strict;

use Test::More;

plan tests =>  2 ;

ok("First test passes");
BAIL_OUT("Pressed the eject button");
ok("Second test passes");

