#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist qw/bad_author/;
use t::Helper;
use t::Frontend;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
    prereq_pm => { 'File::Spec' => 0 },
    # Using MockCPANDist with "bad_author" so the following are ignored
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

my $command = "make test";

# Includes both old and new T::H result text
my $report_output =  << 'HERE';
t\01_Bogus_Module....ok
All tests successful.
Result: PASS
Files=1, Tests=3,  0 wallclock secs ( 0.00 cusr +  0.00 csys =  0.00 CPU)
HERE

my ($got, $prereq_pm);

plan tests => 3 + test_fake_config_plan() + test_report_plan();

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

test_fake_config();

my $case = {};
$case->{label} = "bad author";
$case->{expected_grade} = "pass";
$case->{dist} = $mock_dist;
$case->{dist}{prereq_pm} = $case->{prereq_pm};
$case->{command} = $command;
$case->{output} = [ map {$_ . "\n" } 
                    split( "\n", $report_output) ];
$case->{original} = $report_output;

my $result = test_report( $case ); 
 
is( $result->{author}, "Author",
    "generic author name used"
);

is( $result->{author_id}, q{},
    "author id left blank"
);


