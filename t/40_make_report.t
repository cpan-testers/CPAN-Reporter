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
    {
        name => 't-Pass',
        eumm_success => 1,
        eumm_grade => "pass",
        eumm_msg => "No errors",
        mb_success => 1,
        mb_grade => "pass",
        mb_msg => "No errors",
    },
    {
        name => 'make-Fail',
        eumm_success => 0,
        eumm_grade => "unknown",
        eumm_msg => "Stopped with an error",
        mb_success => 0,
        mb_grade => "unknown",
        mb_msg => "Stopped with an error",
    },
    {
        name => 'make-RequirePerl',
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "Perl version too low",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "Perl version too low",
    },
);

plan tests => 1 + test_fake_config_plan() 
                + test_grade_make_plan() * @test_distros;

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
    test_grade_make( $case, $mock_dist ); 
} 
