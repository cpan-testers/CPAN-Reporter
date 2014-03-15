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
# Skip on Win32 except for release testing
#--------------------------------------------------------------------------#

if ( $^O eq "MSWin32" ) {
    plan skip_all => "\$ENV{RELEASE_TESTING} required for Win32 timeout testing", 
        unless $ENV{RELEASE_TESTING};
    eval "use Win32::Job ()";
    plan skip_all => "Can't interrupt hung processes without Win32::Job"
        if $@;
}

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $make = $Config{make};
my $perl = Probe::Perl->find_perl_interpreter();

my %mock_dist_options = (
    prereq_pm       => {
        requires => {
            'File::Spec' => 0,
        },
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);
    
my @cases = (
    {
        label => "t-Pass",
        pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
        name => "t-Pass",
        version => 1.23,
        grade => "pass",
        phase => "test",
        command => "$make test",
        will_send => 1,
    },
    {
        label => "t-Fail",
        pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
        name => "t-Fail",
        version => 1.23,
        grade => "fail",
        phase => "test",
        command => "$make test",
        will_send => 1,
    },
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
    test_fake_config( command_timeout => 3 );
    test_dispatch( 
        $case, 
        will_send => $case->{will_send},
    );
}

