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
        name => 't-PrereqMiss',
        prereq => { 'Bogus::Module::Doesnt::Exist' => 0 },
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "Prerequisite missing",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "Prerequisite missing",
    },
    {
        name => 'test.pl-PrereqMiss',
        prereq => { 'Bogus::Module::Doesnt::Exist' => 0 },
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "Prerequisite missing",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "Prerequisite missing",
    },
    {
        name => 't-PrereqFail',
        prereq => { 'File::Spec' => 99999.9 },
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "Prerequisite version too low",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "Prerequisite version too low",
    },
    {
        name => 'test.pl-PrereqFail',
        prereq => { 'File::Spec' => 99999.9 },
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "Prerequisite version too low",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "Prerequisite version too low",
    },
    {
        name => 't-LowPerl',
        prereq => { },
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "Perl version too low",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "Perl version too low",
    },
    {
        name => 'test.pl-LowPerl',
        prereq => { },
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "Perl version too low",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "Perl version too low",
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
