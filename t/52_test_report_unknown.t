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
    # unknown
    {
        name => 'NoTestDir',
        eumm_success => 1,
        eumm_grade => "unknown",
        eumm_msg => "No tests provided",
        mb_success => 1,
        mb_grade => "unknown",
        mb_msg => "No tests provided",
    },
    {
        name => 'NoTestFiles',
        eumm_success => 1,
        eumm_grade => "unknown",
        eumm_msg => "No tests were run",
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
