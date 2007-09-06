# CPAN::Reporter tests
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::Helper;
use t::Frontend;

#--------------------------------------------------------------------------#
# Bailout if we're on a broken dev version of Test::Harness
#--------------------------------------------------------------------------#
require Test::Harness;
if ( $Test::Harness::VERSION eq "2.99_01" ) {
    warn "Detected Test::Harness 2.99_01\n";
    BAIL_OUT("Your Test::Harness conflicts with CPAN::Reporter")
}

#--------------------------------------------------------------------------#

my @api = qw(
    configure 
    grade_PL 
    grade_make
    grade_test 
    record_command 
    test 
);

my @modules = qw(
    CPAN::Reporter
    CPAN::Reporter::Config
    CPAN::Reporter::History
);

plan tests =>  @api + @modules;

require_ok( $_ ) for @modules;

can_ok( 'CPAN::Reporter', $_ ) for @api;

