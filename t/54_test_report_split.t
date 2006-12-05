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
        name => 'test.pl-NoOutput-OK',
        eumm_success => 1,
        eumm_grade => "pass",
        eumm_msg => "'make test' no errors",
        mb_success => 0,
        mb_grade => "fail",
        mb_msg => "Tests had no output",
    },
    {
        name => 't-test.pl-Pass-NoOutput-OK',
        eumm_success => 1,
        eumm_grade => "pass",
        eumm_msg => "'make test' no errors",
        mb_success => 0,
        mb_grade => "fail",
        mb_msg => "Distribution had failing tests",
    },
);

plan tests => 1 + test_fake_config_plan() + test_dist_plan() * @test_distros;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "Bogus-Module",
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
