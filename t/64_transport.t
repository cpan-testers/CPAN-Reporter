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

plan tests => 1 + 4 * (1 + test_fake_config_plan + test_dispatch_plan);

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

is( Test::Reporter::Mocked->transport(), 'Metabase',
    "by default, transport should be be set to Metabase"
);

#--------------------------------------------------------------------------#
# transport set in config
#--------------------------------------------------------------------------#

for my $transport ( qw/Metabase Mail::Send/ ) {

    test_fake_config( %{$case->{options}}, transport => $transport );

    test_dispatch( 
        $case, 
        will_send => $case->{will_send},
    );

    is( Test::Reporter::Mocked->transport(), $transport, 
        "transport $transport in config was properly set"
    );

}

#--------------------------------------------------------------------------#
# invalid transport
#--------------------------------------------------------------------------#

test_fake_config( %{$case->{options}}, transport => 'LWP' );

my ($stdout, $stderr) = test_dispatch( 
    $case, 
    will_send => 0,
);

like( $stdout, "/'LWP' is invalid/",
    "saw invalid transport warnings"
);
