#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "Bogus::Module",
    prereq_pm => {},
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

my $command = "make test";

my %report_output = (
    'pass' => << 'HERE',
t\01_CPAN_Reporter....ok
All tests successful.
Files=1, Tests=3,  0 wallclock secs ( 0.00 cusr +  0.00 csys =  0.00 CPU)
HERE

    'fail' => << 'HERE',
t\09_option_parsing....
t\09_option_parsing....NOK 2#   Failed test 'foo'
DIED. FAILED test 2
Failed 1/1 test programs. 1/2 subtests failed.
HERE

    'unknown' => << 'HERE',
'No tests defined for Bogus::Module extension.'
}
HERE

    'na' => << 'HERE',
t/01_Bogus....dubious
        Test returned status 2 (wstat 512, 0x200)
FAILED--1 test script could be run, alas--no output ever seen
HERE

);
    
my ($got, $prereq_pm);

my @cases = (
    {
        label => "pass",
        prereq_pm => {
            'File::Spec' => 0,
        },
    },
    {
        label => "fail",
        prereq_pm => {
            'File::Spec' => 0,
        },
    },
    {
        label => "unknown",
        prereq_pm => {
            'File::Spec' => 0,
        },
    },
    {
        label => "na",
        prereq_pm => {
            'Bogus::Module' => 0,
        },
    },
);


plan tests => 1 + test_fake_config_plan()
                + test_report_plan() * @cases;

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

test_fake_config();

$prereq_pm = CPAN::Reporter::_prereq_report( $mock_dist );

for my $case ( @cases ) {
    $case->{expected_grade} = $case->{label};
    $case->{dist} = $mock_dist;
    $case->{dist}{prereq_pm} = $case->{prereq_pm};
    $case->{command} = $command;
    $case->{output} = [ map {$_ . "\n" } 
                        split( "\n", $report_output{$case->{label}}) ];
    $case->{original} = $report_output{$case->{label}};
    test_report( $case );
}



