#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;
use Config;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
    prereq_pm => {},
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

my ($got, $prereq_pm);

my %standard_case_info = (
    phase => "test",
    command => "$Config{make} test",
);

my @cases = (
    {
        expected_grade => "pass",
        name => "t-Pass",
    },
    {
        expected_grade => "fail",
        name => "t-Fail",
    },
    {
        expected_grade => "unknown",
        name => "NoTestFiles",
    },
    {
        expected_grade => "na",
        name => "t-NoSupport",
    },
    {
        expected_grade => "fail",
        name => "t-Fail-LongOutput",
    },
    {
        expected_grade => "pass",
        name => "t-Pass",
        automated => 1,
    },
);


plan tests => 1 + test_fake_config_plan()
                + test_report_plan() * @cases;

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

test_fake_config( send_report => "yes" );

for my $case ( @cases ) {
    local $ENV{AUTOMATED_TESTING} = $case->{automated};
    $case->{label} = $case->{name};
    $case->{dist} = $mock_dist;
    $case->{$_} = $standard_case_info{$_} for keys %standard_case_info;
    test_report( $case );
}



