#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Frontend;
use t::Helper;

my @test_distros = (
    # discards
    {
        name => 'PL-PrereqMiss',
        prereq => { 'requires' => {'Unavailable::Module' => 0} },
        eumm_success => 0,
        eumm_grade => "discard",
        mb_success => 0,
        mb_grade => "discard",
    },
    {
        name => 'PL-PrereqMissOK',
        prereq => { 'requires' => {'Unavailable::Module' => 0} },
        eumm_success => 1,
        eumm_grade => "pass",
        mb_success => 1,
        mb_grade => "pass",
    },
    {
        name => 'PL-PrereqFail',
        prereq => { 'requires' => { 'File::Spec' => 99999.9 } },
        eumm_success => 0,
        eumm_grade => "discard",
        mb_success => 0,
        mb_grade => "discard",
    },
    {
        name => 'PL-NoMakefileOrBuild',
        prereq => {},
        eumm_success => 0,
        eumm_grade => "discard",
        mb_success => 0,
        mb_grade => "discard",
    },
    {
        name => 'PL-ConfigRequires',
        prereq => {},
        eumm_success => 0,
        eumm_grade => "discard",
        mb_success => 0,
        mb_grade => "discard",
    },
    {
        name => 'PL-ConfigRequiresError',
        prereq => {},
        eumm_success => 0,
        eumm_grade => "unknown",
        mb_success => 0,
        mb_grade => "unknown",
    },
);

plan tests => 1 + test_fake_config_plan() 
                + test_grade_PL_plan() * @test_distros;

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
        pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
        prereq_pm       => $case->{prereq},
        author_id       => "JOHNQP",
        author_fullname => "John Q. Public",
    );

    test_grade_PL( $case, $mock_dist ); 
} 
