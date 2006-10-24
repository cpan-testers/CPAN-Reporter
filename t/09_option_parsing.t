#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use IO::CaptureOutput qw/capture/;

my @good_cases = (
    {
        label   => "empty input",
        option  => "edit_report",
        input   => "",
        output  => {
            default => "ask/no",
        },
    },
    {
        label   => "action (by itself)",
        option  => "edit_report",
        input   => "yes",
        output  => {
            default => "yes",
        },
    },
    {
        label   => "grade (by itself)",
        option  => "edit_report",
        input   => "fail",
        output  => {
            "fail"  => "yes",
            default => "ask/no",
        },
    },
    {
        label   => "default:action",
        option  => "edit_report",
        input   => "default:no",
        output  => {
            default => "no",
        },
    },
    {
        label   => "grade:action",
        option  => "edit_report",
        input   => "fail:yes",
        output  => {
            "fail"  => "yes",
            default => "ask/no",
        },
    },
    {
        label   => "grade:action action",
        option  => "edit_report",
        input   => "fail:yes no",
        output  => {
            "fail"  => "yes",
            default => "no",
        },
    },
    {
        label   => "grade:action action grade:action",
        option  => "edit_report",
        input   => "fail:yes no fail:no",
        output  => {
            "fail"  => "no",
            default => "no",
        },
    },
    {
        label   => "grade:action action grade2:action",
        option  => "edit_report",
        input   => "fail:yes no na:no",
        output  => {
            "fail"  => "yes",
            "na"    => "no",
            default => "no",
        },
    },
);
        
my @bad_cases = (
    {
        label   => "bad_action",
        option  => "edit_report",
        input   => "nope",
        msg     => 
            "/\\AIgnoring invalid option 'nope' for 'edit_report'/",
    },
);

plan tests => 1 + @good_cases + @bad_cases; 

#--------------------------------------------------------------------------#
# Begin tests
#--------------------------------------------------------------------------#

require_ok( "CPAN::Reporter" );

for my $case ( @good_cases ) {
    my $got = CPAN::Reporter::_parse_option( $case->{option}, $case->{input} );
    is_deeply( $got, $case->{output}, $case->{label} );
}

for my $case ( @bad_cases ) {
    my $stderr;
    capture sub { 
        my $got = 
        CPAN::Reporter::_parse_option( $case->{option}, $case->{input} );
    }, undef, \$stderr;
    like( $stderr, $case->{msg}, $case->{label} );
}

