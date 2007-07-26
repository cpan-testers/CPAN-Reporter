# CPAN::Reporter tests
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

use Test::More;
use t::Helper;
use t::Frontend;

#--------------------------------------------------------------------------#
# autoflush to keep output in order
#--------------------------------------------------------------------------#

my $stdout = select(STDERR);
$|++;
select($stdout);
$|++;

#--------------------------------------------------------------------------#

my @api = qw(
    configure 
    grade_PL 
    grade_make
    grade_test 
    record_command 
    test 
);

plan tests =>  1 + @api ;

require_ok( 'CPAN::Reporter' );

for my $fcn ( @api ) {
    can_ok( 'CPAN::Reporter', $fcn );
}

