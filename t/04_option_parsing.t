#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::Frontend;
use t::Helper;
use IO::CaptureOutput qw/capture/;

my @good_cases = (
    {
        label   => "empty input",
        option  => "edit_report",
        input   => "",
        output  => {
            default => "no",
        }
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
    {
        label   => "grade/grade2:action",
        option  => "edit_report",
        input   => "fail/na:ask/yes",
        output  => {
            "fail"  => "ask/yes",
            "na"    => "ask/yes",
        },
    },
    {
        label   => "grade/grade2",
        option  => "edit_report",
        input   => "fail/na",
        output  => {
            "fail"  => "yes",
            "na"    => "yes",
        },
    },
);
        
my @bad_cases = (
    {
        label   => "bad grade",
        option  => "edit_report",
        input   => "failed",
        output  => undef,
        msg     => 
            "/ignoring invalid grade:action 'failed' for 'edit_report'/",
    },
    {
        label   => "bad action",
        option  => "edit_report",
        input   => "fail:run-away",
        output  => undef,
        msg     => 
            "/ignoring invalid action 'run-away' in 'fail:run-away' for 'edit_report'/",
    },
);

plan tests => 1 + 2 * ( @good_cases + @bad_cases ); 

#--------------------------------------------------------------------------#
# Begin tests
#--------------------------------------------------------------------------#

require_ok( "CPAN::Reporter::Config" );

for my $case ( @good_cases, @bad_cases ) {
    my ($got, $stdout, $stderr);
    capture sub { 
        $got = CPAN::Reporter::Config::_validate_grade_action_pair( 
            $case->{option}, $case->{input} 
        );
    }, \$stdout, \$stderr;
    is_deeply( $got, $case->{output}, $case->{label} );
    if ( $case->{msg} ) {
        like( $stdout, $case->{msg}, $case->{label} );
    }
    else {
        is( $stdout, '', "No warnings seen" );
    }
}

