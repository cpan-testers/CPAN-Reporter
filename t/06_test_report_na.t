#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;

my @test_distros = (
    # na 
    {
        name => 'Bogus-t-PrereqFail',
        prereq => { 'Bogus::Module::Doesnt::Exist' => 0 },
        eumm_success => 0,
        eumm_grade => "na",
        mb_success => 0,
        mb_grade => "na",
    },
    {
        name => 'Bogus-t-LowPerl',
        prereq => { },
        eumm_success => 0,
        eumm_grade => "na",
        mb_success => 0,
        mb_grade => "na",
    },
);

plan tests => 1 + test_fake_config_plan() + test_dist_plan() * @test_distros;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

test_fake_config();

for my $case ( @test_distros ) {
    my $mock_dist = t::MockCPANDist->new( 
        pretty_id => "Bogus::Module",
        prereq_pm       => $case->{prereq},
        author_id       => "JOHNQP",
        author_fullname => "John Q. Public",
    );

    test_dist( $case, $mock_dist ); 
} 
