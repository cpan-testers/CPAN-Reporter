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
        label => "pass",
        name => "t-Pass",
    },
    {
        label => "fail",
        name => "t-Fail",
    },
    {
        label => "unknown",
        name => "NoTestFiles",
    },
    {
        label => "na",
        name => "t-NoSupport",
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
    $case->{expected_grade} = $case->{label};
    $case->{dist} = $mock_dist;
    $case->{$_} = $standard_case_info{$_} for keys %standard_case_info;
#    $case->{exit_value} = $case->{label} eq 'pass' ? 0 : 1 << 8 ;
#    $case->{original} = $report_output{$case->{label}};
    test_report( $case );
}



