# CPAN::Reporter tests
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }
use Test::More;

#--------------------------------------------------------------------------#
# autoflush to keep output in order
#--------------------------------------------------------------------------#

my $stdout = select(STDERR);
$|++;
select($stdout);
$|++;

#--------------------------------------------------------------------------#

my @api = qw/test configure/;

plan tests =>  1 + @api ;

require_ok( 'CPAN::Reporter' );

for my $fcn ( @api ) {
    can_ok( 'CPAN::Reporter', $fcn );
}

