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

my %standard_case_info = (
    name => "t-Fail",
    grade => "fail",
    phase => "test",
    command => "make test",
);

my @cases = (
    {
        label => "proper distribution name (tar.gz)",
        pretty_id => "JOHNQP/Bogus-Module-1.21.tar.gz",
        will_send => 1,
    },
    {
        label => "proper distribution name (tar.bz2)",
        pretty_id => "JOHNQP/Bogus-Module-1.22.tar.gz",
        will_send => 1,
    },
    {
        label => "proper distribution name (tgz)",
        pretty_id => "JOHNQP/Bogus-Module-1.23.tgz",
        will_send => 1,
    },
    {
        label => "proper distribution name (zip)",
        pretty_id => "JOHNQP/Bogus-Module-1.24.zip",
        will_send => 1,
    },
    {
        label => "proper distribution name (ZIP)",
        pretty_id => "JOHNQP/Bogus-Module-1.25.ZIP",
        will_send => 1,
    },
    {
        label => "proper distribution name (v1.23)",
        pretty_id => "JOHNQP/Bogus-Module-v1.26.tgz",
        will_send => 1,
    },
    {
        label => "proper distribution name (1.2_01)",
        pretty_id => "JOHNQP/Bogus-Module-1.2_01.tgz",
        will_send => 1,
    },
    {
        label => "proper distribution name (v1.2a)",
        pretty_id => "JOHNQP/Bogus-Module-v1.2a.tgz",
        will_send => 1,
    },
    {
        label => "proper distribution name (v1.2_01)",
        pretty_id => "JOHNQP/Bogus-Module-v1.2_02.tgz",
        will_send => 1,
    },
    {
        label => "missing extension",
        pretty_id => "JOHNQP/Bogus-Module-1.31",
        will_send => 0,
    },
    {
        label => "missing version",
        pretty_id => "JOHNQP/Bogus-Module.tgz",
        will_send => 0,
    },
    {
        label => "raw pm file",
        pretty_id => "JOHNQP/Module.pm",
        will_send => 0,
    },
);


plan tests => 2 + test_fake_config_plan()
                + (1 + test_dispatch_plan()) * @cases;

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');
require_ok('CPAN::Reporter::History');

test_fake_config();

for my $case ( @cases ) {
    $case->{dist} = t::MockCPANDist->new( %mock_dist_info );
    $case->{dist}{pretty_id} = $case->{pretty_id};
    $case->{$_} = $standard_case_info{$_} for keys %standard_case_info;
    test_dispatch( $case, will_send => $case->{will_send} );
    my $hist_grade = $case->{will_send} ? 'FAIL' : 'DISCARD';
    ok( scalar CPAN::Reporter::History::have_tested( 
        dist => $case->{dist}->base_id,
        grade => $hist_grade,
      ),
      $case->{dist}->pretty_id . " seen in history as $hist_grade"
    );
}



