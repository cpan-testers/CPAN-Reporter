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
        name => 't-PrereqMiss',
        prereq => { 'Bogus::Module::Doesnt::Exist' => 0 },
        eumm_success => 0,
        eumm_grade => "discard",
        eumm_msg => "Prerequisite missing",
        mb_success => 0,
        mb_grade => "discard",
        mb_msg => "Prerequisite missing",
    },
    {
        name => 't-NoTestsButPrereqMiss',
        prereq => { 'Bogus::Module::Doesnt::Exist' => 0 },
        eumm_success => 0,
        eumm_grade => "discard",
        eumm_msg => "Prerequisite missing",
        mb_success => 0,
        mb_grade => "discard",
        mb_msg => "Prerequisite missing",
    },
    {
        name => 'test.pl-PrereqMiss',
        prereq => { 'Bogus::Module::Doesnt::Exist' => 0 },
        eumm_success => 0,
        eumm_grade => "discard",
        eumm_msg => "Prerequisite missing",
        mb_success => 0,
        mb_grade => "discard",
        mb_msg => "Prerequisite missing",
    },
    {
        name => 't-PrereqFail',
        prereq => { 'File::Spec' => 99999.9 },
        eumm_success => 0,
        eumm_grade => "discard",
        eumm_msg => "Prerequisite version too low",
        mb_success => 0,
        mb_grade => "discard",
        mb_msg => "Prerequisite version too low",
    },
    {
        name => 'test.pl-PrereqFail',
        prereq => { 'File::Spec' => 99999.9 },
        eumm_success => 0,
        eumm_grade => "discard",
        eumm_msg => "Prerequisite version too low",
        mb_success => 0,
        mb_grade => "discard",
        mb_msg => "Prerequisite version too low",
    },
);

plan tests => 1 + test_fake_config_plan() 
                + test_grade_test_plan() * @test_distros;

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

    test_grade_test( $case, $mock_dist ); 
} 
