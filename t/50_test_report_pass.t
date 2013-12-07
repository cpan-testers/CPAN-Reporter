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
    # pass
    {
        name => 't-Pass',
        eumm_success => 1,
        eumm_grade => "pass",
        eumm_msg => "All tests successful",
        mb_success => 1,
        mb_grade => "pass",
        mb_msg => "All tests successful",
    },
    {
        name => 'test.pl-Pass',
        eumm_success => 1,
        eumm_grade => "pass",
        eumm_msg => "'make test' no errors",
        mb_success => 1,
        mb_grade => "pass",
        mb_msg => "All tests successful",
    },
    {
        name => 't-test.pl-Pass-Pass',
        eumm_success => 1,
        eumm_grade => "pass",
        eumm_msg => "'make test' no errors",
        mb_success => 1,
        mb_grade => "pass",
        mb_msg => "All tests successful",
    },
    {
        name => 't-PrereqPerl-OK',
        eumm_success => 1,
        eumm_grade => "pass",
        eumm_msg => "All tests successful",
        mb_success => 1,
        mb_grade => "pass",
        mb_msg => "All tests successful",
    },
    {
        name => 'test.pl-PrereqPerl-OK',
        eumm_success => 1,
        eumm_grade => "pass",
        eumm_msg => "'make test' no errors",
        mb_success => 1,
        mb_grade => "pass",
        mb_msg => "All tests successful",
    },
    {
        name => 't-Recurse-Pass',
        eumm_success => 1,
        eumm_grade => "pass",
        eumm_msg => "'make test' no errors",
        mb_success => 1,
        mb_grade => "pass",
        mb_msg => "All tests successful",
    },
    {
        name => 'custom-NoOutput-OK',
        eumm_success => 1,
        eumm_grade => "pass",
        eumm_msg => "'make test' no errors",
        mb_success => 1,
        mb_grade => "pass",
        mb_msg => "'Build test' no errors",
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
