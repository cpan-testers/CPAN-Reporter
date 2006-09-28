#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;

my @test_distros = (
    # fail
    {
        name => 'Bogus-t-Fail',
        eumm_success => 0,
        eumm_grade => "fail",
        mb_success => 0,
        mb_grade => "fail",
        msg => "Distribution had failing tests",
    },
    {
        name => 'Bogus-test.pl-NoOutput-NOK',
        eumm_success => 0,
        eumm_grade => "fail",
        mb_success => 0,
        mb_grade => "fail",
        msg => "Tests had no output",
    },
    {
        name => 'Bogus-test.pl-Fail',
        eumm_success => 0,
        eumm_grade => "fail",
        mb_success => 0,
        mb_grade => "fail",
        msg => "Distribution had failing tests",
    },
    {
        name => 'Bogus-t-NoOutput',
        eumm_success => 0,
        eumm_grade => "fail",
        mb_success => 0,
        mb_grade => "fail",
        msg => "Tests had no output",
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
