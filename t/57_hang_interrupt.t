use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;
use Config;
use Probe::Perl;
use File::Temp;

#--------------------------------------------------------------------------#
# Skip on Win32 if we don't have Win32::Process
#--------------------------------------------------------------------------#

if ( $^O eq "MSWin32" ) {
    eval "use Win32::Process 0.10 ()";
    plan skip_all => "Can't interrupt hung processes without Win32::Process"
        if $@;
}

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $make = $Config{make};
my $perl = Probe::Perl->find_perl_interpreter();

my %mock_dist_options = (
    prereq_pm       => {
        'File::Spec' => 0,
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);
    
my @cases = (
    {
        label => "PL-Hang",
        pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
        name => "PL-Hang",
        version => 1.23,
        grade => "discard",
        phase => "PL",
        command => "$perl Makefile.PL",
        will_send => 0,
    },
    {
        label => "t-Hang",
        pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
        name => "t-Hang",
        version => 1.23,
        grade => "discard",
        phase => "test",
        command => "$make test",
        will_send => 0,
    },
);

plan tests => 1 + @cases * (test_fake_config_plan() + test_dispatch_plan());

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

# test send_skipfile
for my $case ( @cases ) {
    $case->{dist} = t::MockCPANDist->new(
        pretty_id => $case->{pretty_id},
        %mock_dist_options,
    );
    test_fake_config( command_timeout => 10 );
    test_dispatch( 
        $case, 
        will_send => $case->{will_send},
    );
}

