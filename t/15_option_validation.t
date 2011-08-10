#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::Frontend;
use t::Helper;
use IO::CaptureOutput qw/capture/;
use File::Spec;

my @cases = (
    {
        label   => "skipfile (exists)",
        option  => "cc_skipfile",
        input   => File::Spec->rel2abs("Changes"),
        output   => File::Spec->rel2abs("Changes"),
    },
    {
        label   => "skipfile (missing)",
        option  => "cc_skipfile",
        input   => "afdadfasdfasdf",
        output  => undef,
    },
    {
        label   => "command_timeout (positive)",
        option  => "command_timeout",
        input   => 10,
        output  => 10,
    },
    {
        label   => "command_timeout (negative)",
        option  => "command_timeout",
        input   => -10,
        output  => undef,
    },
    {
        label   => "command_timeout (zero)",
        option  => "command_timeout",
        input   => 0,
        output  => 0,
    },
    {
        label   => "command_timeout (empty)",
        option  => "command_timeout",
        input   => q{},
        output  => undef,
    },
    {
        label   => "command_timeout (undef)",
        option  => "command_timeout",
        input   => undef,
        output  => undef,
    },
    {
        label   => "command_timeout (alpha)",
        option  => "command_timeout",
        input   => "abcd",
        output  => undef,
    },
);

plan tests => 1 + 1 * @cases;

#--------------------------------------------------------------------------#
# Begin tests
#--------------------------------------------------------------------------#

require_ok( "CPAN::Reporter::Config" );

for my $c ( @cases ) {
    my ($got);
    $got = CPAN::Reporter::Config::_validate( $c->{option}, $c->{input} );
    is( $got, $c->{output}, $c->{label} );
}

