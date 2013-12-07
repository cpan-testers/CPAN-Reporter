#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;

my $lt_5006 = $] < 5.006;

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
        name => 'PL-Fail',
        eumm_success => 0,
        eumm_grade => "unknown",
        eumm_msg => "Stopped with an error",
        mb_success => 0,
        mb_grade => "unknown",
        mb_msg => "Stopped with an error",
    },
    {
        name => 'PL-RequirePerl',
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "Perl version too low",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "Perl version too low",
    },
    {
        name => 'PL-MIRequirePerl',
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "Perl version too low",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "Perl version too low",
    },
    {
        name => 'PL-OSUnsupported',
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "This platform is not supported",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "This platform is not supported",
    },
    {
        name => 'PL-warn-OSUnsupported',
        eumm_success => 0,
        eumm_grade => "na",
        eumm_msg => "This platform is not supported",
        mb_success => 0,
        mb_grade => "na",
        mb_msg => "This platform is not supported",
    },
    {
        name => 't-PrereqPerl-NOK-our',
        prereq => { perl => 42 },
        eumm_success => $lt_5006 ? 0 : 1,
        eumm_grade => $lt_5006 ? "na" : "pass",
        eumm_msg => $lt_5006 ? "Perl version too low" : "No errors",
        mb_success => $lt_5006 ? 0 : 1,
        mb_grade => $lt_5006 ? "na" : "pass",
        mb_msg => $lt_5006 ? "Perl version too low" : "No errors",
    },
);

plan tests => 1 + test_fake_config_plan() 
                + test_grade_PL_plan() * @test_distros;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my %mock_dist_args = ( 
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
    my $mock_dist = t::MockCPANDist->new( 
        %mock_dist_args, %{$case->{prereq_pm}}
    );
    test_grade_PL( $case, $mock_dist ); 
} 
