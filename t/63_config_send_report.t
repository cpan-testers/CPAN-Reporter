#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;
use Config;
use Probe::Perl;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $make = $Config{make};
my $perl = Probe::Perl->find_perl_interpreter();
$perl = qq{"$perl"};

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
    prereq_pm       => {
        requires => { 'File::Spec' => 0 },
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);
    
my @cases = (
    {
        label => "send_PL_report 'no'",
        name => "PL-Fail",
        version => 1.23,
        grade => "fail",
        phase => "PL",
        command => "$perl Makefile.PL",
        will_send => 0,
        options => {
            send_report => "yes",
            send_PL_report => "no", 
        },
    },
    {
        label => "send_make_report 'no'",
        label => "first make failure",
        name => "make-Fail",
        version => 1.23,
        grade => "fail",
        phase => "make",
        command => "$make",
        will_send => 0,
        options => { 
            send_report => "yes",
            send_make_report => "no", 
        },
    },
    {
        label => "send_test_report 'no'",
        name => "t-Fail",
        grade => "fail",
        phase => "test",
        command => "$make test",
        will_send => 0,
        options => { 
            send_report => "yes",
            send_test_report => "no", 
        },
    },
    {
        label => "send_PL_report 'yes'",
        name => "PL-Fail",
        version => 1.23,
        grade => "fail",
        phase => "PL",
        command => "$perl Makefile.PL",
        will_send => 1,
        options => {
            send_report => "no",
            send_PL_report => "yes", 
        },
    },
    {
        label => "send_make_report 'yes'",
        label => "first make failure",
        name => "make-Fail",
        version => 1.23,
        grade => "fail",
        phase => "make",
        command => "$make",
        will_send => 1,
        options => { 
            send_report => "no",
            send_make_report => "yes", 
        },
    },
    {
        label => "send_test_report 'yes'",
        name => "t-Fail",
        grade => "fail",
        phase => "test",
        command => "$make test",
        will_send => 1,
        options => { 
            send_report => "no",
            send_test_report => "yes", 
        },
    },
);

my $expected_history_lines = 1; # opening comment line

for my $c ( @cases ) {
    $expected_history_lines++ if not $c->{is_dup}
}

plan tests => 1 + @cases * ( test_fake_config_plan() + test_dispatch_plan() );

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

my @results;

for my $case ( @cases ) {
    $case->{dist} = $mock_dist;
    test_fake_config( %{$case->{options}} );
    test_dispatch( 
        $case, 
        will_send => $case->{will_send},
    );
}

