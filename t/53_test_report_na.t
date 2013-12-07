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
    # na 
    {
        name => 't-PrereqPerl-NOK',
        prereq => { 'requires' => { perl => 42 } },
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "Perl version too low",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "Perl version too low",
    },
    {
        name => 'test.pl-PrereqPerl-NOK',
        prereq => { 'requires' => { perl => 42 } },
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "Perl version too low",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "Perl version too low",
    },
    {
        name => 't-NoSupport',
        prereq => { },
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "This platform is not supported",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "This platform is not supported",
    },
    {
        name => 't-OSUnsupported',
        prereq => { },
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "This platform is not supported",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "This platform is not supported",
    },
    {
        name => 'test.pl-OSUnsupported',
        prereq => { },
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "This platform is not supported",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "This platform is not supported",
    },
    {
        name => 't-RequirePerl',
        prereq => { },
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "Perl version too low",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "Perl version too low",
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
