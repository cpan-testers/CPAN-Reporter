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
    pretty_id => "PLACEHOLDER",
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
        label => "proper distribution name (tar.gz)",
        pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
        should_work => 1,
    },
    {
        label => "proper distribution name (tar.bz2)",
        pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
        should_work => 1,
    },
    {
        label => "proper distribution name (tgz)",
        pretty_id => "JOHNQP/Bogus-Module-1.23.tgz",
        should_work => 1,
    },
    {
        label => "proper distribution name (zip)",
        pretty_id => "JOHNQP/Bogus-Module-1.23.zip",
        should_work => 1,
    },
    {
        label => "proper distribution name (ZIP)",
        pretty_id => "JOHNQP/Bogus-Module-1.23.ZIP",
        should_work => 1,
    },
    {
        label => "proper distribution name (v1.23)",
        pretty_id => "JOHNQP/Bogus-Module-v1.23.tgz",
        should_work => 1,
    },
    {
        label => "proper distribution name (1.2_01)",
        pretty_id => "JOHNQP/Bogus-Module-1.2_01.tgz",
        should_work => 1,
    },
    {
        label => "proper distribution name (v1.2a)",
        pretty_id => "JOHNQP/Bogus-Module-v1.2a.tgz",
        should_work => 1,
    },
    {
        label => "proper distribution name (v1.2_01)",
        pretty_id => "JOHNQP/Bogus-Module-v1.2_01.tgz",
        should_work => 1,
    },
    {
        label => "missing extension",
        pretty_id => "JOHNQP/Bogus-Module-1.23",
        should_work => 0,
    },
    {
        label => "missing version",
        pretty_id => "JOHNQP/Bogus-Module.tgz",
        should_work => 0,
    },
    {
        label => "raw pm file",
        pretty_id => "JOHNQP/Module.pm",
        should_work => 0,
    },
);


plan tests => 1 + test_fake_config_plan()
                + test_dispatch_plan() * @cases;

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

test_fake_config();

for my $case ( @cases ) {
    $case->{dist} = t::MockCPANDist->new( %mock_dist_info );
    $case->{dist}{pretty_id} = $case->{pretty_id};
    $case->{command} = $command;
    $case->{output} = [ map {$_ . "\n" } 
                        split( "\n", $mock_output) ];
    test_dispatch( $case, should_work => $case->{should_work} );
}



