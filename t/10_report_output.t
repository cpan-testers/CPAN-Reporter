#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "Bogus::Module",
    prereq_pm       => {
        'File::Spec' => 0,
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

my $command = "make test";

my $pass_output = << 'HERE';
t\01_CPAN_Reporter....ok
All tests successful.
Files=1, Tests=3,  0 wallclock secs ( 0.00 cusr +  0.00 csys =  0.00 CPU)
HERE

my $fail_output = << 'HERE';
t\09_option_parsing....
t\09_option_parsing....NOK 2#   Failed test 'foo'
DIED. FAILED test 2
Failed 1/1 test programs. 1/2 subtests failed.
HERE

my ($got, $prereq_pm);

my @cases = (
    {
        label => "pass",
        dist => $mock_dist,
        command => $command,
        output => [ map {$_ . "\n" } split( "\n", $pass_output) ],
        original => $pass_output,
    },
    {
        label => "fail",
        dist => $mock_dist,
        command => $command,
        output => [ map { $_ . "\n" } split( "\n", $fail_output) ],
        original => $fail_output,
    },
);


plan tests => 1 + test_fake_config_plan()
                + test_process_report_plan() * @cases;

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

test_fake_config();

$prereq_pm = CPAN::Reporter::_prereq_report( $mock_dist );

for my $case ( @cases ) {
    test_process_report( $case, $case->{label} );
}



