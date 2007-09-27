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
        'File::Spec' => 0,
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

plan tests => 2 + 4 * (1 + test_fake_config_plan + test_dispatch_plan);

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

is( Test::Reporter::Mocked->transport(), undef,
    "by default, transport should be not be set"
);

#--------------------------------------------------------------------------#
# transport set in config
#--------------------------------------------------------------------------#

for my $transport ( qw/Net::SMTP Mail::Send/ ) {

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
    will_send => $case->{will_send},
);

is( Test::Reporter::Mocked->transport(), "Net::SMTP", 
    "invalid transport falls back to Net::SMTP"
);

like( $stdout, "/doesn't recognize 'LWP' as a valid transport/",
    "saw invalid transport warnings"
);
