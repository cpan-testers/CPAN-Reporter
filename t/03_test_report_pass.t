#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;

my @test_distros = (
    # pass
    {
        name => 'Bogus-t-Pass',
        eumm_success => 1,
        eumm_grade => "pass",
        mb_success => 1,
        mb_grade => "pass",
    },
    {
        name => 'Bogus-test.pl-Pass',
        eumm_success => 1,
        eumm_grade => "pass",
        mb_success => 1,
        mb_grade => "pass",
    },
);

plan tests => 1 + test_fake_config_plan() + test_dist_plan() * @test_distros;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "Bogus::Module",
    prereq_pm       => {
        'File::Spec' => 0,
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

test_fake_config();

for my $case ( @test_distros ) {
    test_dist( $case, $mock_dist ); 
} 
