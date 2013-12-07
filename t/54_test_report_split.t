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
    # split pass/fail
    {
        name => 't-test.pl-Pass-NoOutput-OK',
        eumm_success => 1,
        eumm_grade => "pass",
        eumm_msg => "'make test' no errors",
        mb_success => 0,
        mb_grade => "fail",
        mb_msg => "One or more tests failed",
    },
    {
        name => 't-Recurse-Fail-t',
        eumm_success => 0,
        eumm_grade => "fail",
        eumm_msg => "'make test' error detected",
        mb_success => 1,
        mb_grade => "unknown",
        mb_msg => "No tests provided",
    },
    {
        name => 't-Recurse-Fail-test.pl',
        eumm_success => 0,
        eumm_grade => "fail",
        eumm_msg => "'make test' error detected",
        mb_success => 1,
        mb_grade => "unknown",
        mb_msg => "No tests provided",
    },
    {
        name => 'NoTestTarget',
        eumm_success => 1,
        eumm_grade => "unknown",
        eumm_msg => "No make test target",
        mb_success => 1,
        mb_grade => "unknown",
        mb_msg => "No tests provided",
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
