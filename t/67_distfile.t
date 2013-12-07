use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;
use Config;
use IO::CaptureOutput;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $make = $Config{make};

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
    prereq_pm       => {
        requires => { 'File::Spec' => 0 },
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);
    
my $case = {
    label => "t-Pass",
    name => "t-Pass",
    dist => $mock_dist,
    version => 1.23,
    grade => "pass",
    phase => "test",
    command => "$make test",
    will_send => 1,
    options => {
        send_report => "yes",
    },
};

plan tests => 1 + 1 * (1 + test_fake_config_plan + test_dispatch_plan);

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

#--------------------------------------------------------------------------#
# no transport advanced option set
#--------------------------------------------------------------------------#

test_fake_config( %{$case->{options}} );

test_dispatch( 
    $case, 
    will_send => $case->{will_send},
);

is( Test::Reporter::Mocked->distfile(), $mock_dist->{pretty_id},
    "CPAN::Reporter sets Test::Reporter->distfile"
);

