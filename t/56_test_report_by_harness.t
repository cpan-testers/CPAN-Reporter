#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;

require Test::Harness;
my $harness_version = Test::Harness->VERSION;
my $is_th2xx = $harness_version < 3;
my $is_th3xx = $harness_version >= 3;
my $is_th305 = $harness_version >= '3.05';

# every distro must have th2xx as a fallback
my @test_distros = (
    {
        name => 't-NoOutput',
        th2xx => {
            eumm_success => 1,
            eumm_grade => "unknown",
            eumm_msg => "No tests were run",
            mb_success => 1,
            mb_grade => "unknown",
            mb_msg => "No tests were run",
        },
        th305 => {
            eumm_success => 0,
            eumm_grade => "fail",
            eumm_msg => "One or more tests failed",
            mb_success => 0,
            mb_grade => "fail",
            mb_msg => "One or more tests failed",
        },
    },
    {
        name => 't-NoOutput-die',
        th2xx => {
            eumm_success => 1,
            eumm_grade => "unknown",
            eumm_msg => "No tests were run",
            mb_success => 1,
            mb_grade => "unknown",
            mb_msg => "No tests were run",
        },
        th305 => {
            eumm_success => 0,
            eumm_grade => "fail",
            eumm_msg => "One or more tests failed",
            mb_success => 0,
            mb_grade => "fail",
            mb_msg => "One or more tests failed",
        },
    },
    {
        name => 'test.pl-NoOutput-OK',
        th2xx => {
            eumm_success => 1,
            eumm_grade => "pass",
            eumm_msg => "'make test' no errors",
            mb_success => 1,
            mb_grade => "unknown",
            mb_msg => "No tests were run",
        },
        th305 => {
            eumm_success => 1,
            eumm_grade => "pass",
            eumm_msg => "'make test' no errors",
            mb_success => 0,
            mb_grade => "fail",
            mb_msg => "One or more tests failed",
        },
    },
    {
        name => 'test.pl-NoOutput-NOK',
        th2xx => {
            eumm_success => 0,
            eumm_grade => "fail",
            eumm_msg => "'make test' error detected",
            mb_success => 1,
            mb_grade => "unknown",
            mb_msg => "No tests were run",
        },
        th305 => {
            eumm_success => 0,
            eumm_grade => "fail",
            eumm_msg => "'make test' error detected",
            mb_success => 0,
            mb_grade => "fail",
            mb_msg => "One or more tests failed",
        },
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
    my $target_version = $is_th305 && exists $case->{th305} ? "th305"
                       : $is_th3xx && exists $case->{th3xx} ? "th3xx"
                       :                                      "th2xx" 
                       ;

    my %target_case = ( 
        name => $case->{name},
        %{$case->{$target_version}},
    );
    test_grade_test( \%target_case, $mock_dist ); 
} 
