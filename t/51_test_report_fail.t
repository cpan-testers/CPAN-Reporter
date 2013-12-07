#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;

my @test_distros = (
    # fail
    {
        name => 't-BailOut',
        eumm_success => 0,
        eumm_grade => "fail",
        eumm_msg => "Bailed out of tests",
        mb_success => 0,
        mb_grade => "fail",
        mb_msg => "Bailed out of tests",
    },
    {
        name => 't-Fail',
        eumm_success => 0,
        eumm_grade => "fail",
        eumm_msg => "One or more tests failed",
        mb_success => 0,
        mb_grade => "fail",
        mb_msg => "One or more tests failed",
    },
    {
        name => 't-MultipleMatch',
        eumm_success => 0,
        eumm_grade => "fail",
        eumm_msg => "One or more tests failed",
        mb_success => 0,
        mb_grade => "fail",
        mb_msg => "One or more tests failed",
    },
    {
        name => 'test.pl-Fail',
        eumm_success => 0,
        eumm_grade => "fail",
        eumm_msg => "'make test' error detected",
        mb_success => 0,
        mb_grade => "fail",
        mb_msg => "One or more tests failed",
    },
    {
        name => 't-test.pl-Fail-Pass',
        eumm_success => 0,
        eumm_grade => "fail",
        eumm_msg => "'make test' error detected",
        mb_success => 0,
        mb_grade => "fail",
        mb_msg => "One or more tests failed",
    },
    {
        name => 't-test.pl-Pass-NoOutput-NOK',
        eumm_success => 0,
        eumm_grade => "fail",
        eumm_msg => "'make test' error detected",
        mb_success => 0,
        mb_grade => "fail",
        mb_msg => "One or more tests failed",
    },
    {
        name => 'custom-NoOutput-NOK',
        eumm_success => 0,
        eumm_grade => "fail",
        eumm_msg => "'make test' error detected",
        mb_success => 0,
        mb_grade => "fail",
        mb_msg => "'Build test' error detected",
    },
);

plan tests => 1 + test_fake_config_plan() 
                + test_grade_test_plan() * @test_distros;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
    prereq_pm       => {
        requires => { 'File::Spec' => 0 },
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
    test_grade_test( $case, $mock_dist ); 
} 
