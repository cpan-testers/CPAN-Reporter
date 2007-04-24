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

my %mock_dist_info = ( 
    pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
    prereq_pm => {},
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

my $command = "make test";

my $mock_output = << 'HERE',
t\09_option_parsing....
t\09_option_parsing....NOK 2#   Failed test 'foo'
DIED. FAILED test 2
Failed 1/1 test programs. 1/2 subtests failed.
HERE
    
my @cases = (
    {
        label => "first run",
        send_duplicates => "no",
        should_work => 1,
    },
    {
        label => "second run (no duplicates)",
        send_duplicates => "no",
        should_work => 0,
    },
    {
        label => "third run (send duplicates)",
        send_duplicates => "yes",
        should_work => 1,
    },
);


plan tests => 1 + @cases * ( test_fake_config_plan() + test_dispatch_plan() );

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');


for my $case ( @cases ) {
    test_fake_config( send_duplicates => $case->{send_duplicates} );
    $case->{dist} = t::MockCPANDist->new( %mock_dist_info );
    $case->{command} = $command;
    $case->{output} = [ map {$_ . "\n" } 
                        split( "\n", $mock_output) ];
    test_dispatch( $case, should_work => $case->{should_work} );
}



