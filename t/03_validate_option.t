#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::Helper;
use IO::CaptureOutput qw/capture/;

my @cases = (
    {
        label   => "action (by itself)",
        input   => "yes",
        output  => [
            default => "yes",
        ],
    },
    {
        label   => "grade (by itself)",
        input   => "fail",
        output  => [
            "fail"  => "yes",
        ],
    },
    {
        label   => "default:action",
        input   => "default:no",
        output  => [
            default => "no",
        ],
    },
    {
        label   => "grade:action",
        input   => "fail:yes",
        output  => [
            "fail"  => "yes",
        ],
    },
    {
        label   => "grade/grade2:action",
        input   => "fail/na:ask/yes",
        output  => [
            "fail"  => "ask/yes",
            "na"    => "ask/yes",
        ],
    },
    {
        label   => "grade/grade2",
        input   => "fail/na",
        output  => [
            "fail"  => "yes",
            "na"    => "yes",
        ],
    },
    {
        label   => "bad grade:action",
        input   => "failed",
        output  => [],
    },
);
        

plan tests => 1 + @cases; 

#--------------------------------------------------------------------------#
# Begin tests
#--------------------------------------------------------------------------#

require_ok( "CPAN::Reporter" );

for my $case ( @cases ) {
    my $got = [ CPAN::Reporter::_validate_grade_action( $case->{input} )];
    is_deeply( $got, $case->{output}, $case->{label} );
}

