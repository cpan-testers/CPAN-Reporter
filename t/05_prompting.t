#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::Helper;
use t::Frontend;
use IO::CaptureOutput qw/capture/;

my @cases = (
    "default:yes",
    "default:no",
    "default:ask/yes",
    "default:ask/no",
    "default:ask/no fail:ask/yes na:yes unknown:no",
);

plan tests => 1 + 4 * @cases;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $option_name = "edit_report";
my ($got);

#--------------------------------------------------------------------------#
# Begin tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

local $ENV{PERL_MM_USE_DEFAULT} = 1;

for my $c ( @cases ) {
    my $config = { $option_name => $c };
    my $parsed = CPAN::Reporter::Config::_validate_grade_action_pair( 
        $option_name, $c 
    );
    for my $grade ( qw/pass fail na unknown/ ) {
        capture {
            $got = CPAN::Reporter::_prompt( $config, $option_name, $grade );
        };
        my $expected = $parsed->{$grade} || $parsed->{default};
        # convert ask/* to *
        $expected =~ s{ask/?}{};
        $expected = "no" if not length $expected;
        is( $got, $expected , 
            "'$c' for '$grade'"
        );
    }
}

