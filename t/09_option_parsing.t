#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;

my @cases = (
    {
        label   => "foo",
        input   => "yes",
        output  => {
            default => "yes",
        },
    },
);
        
plan tests => 1 + @cases; 

#--------------------------------------------------------------------------#
# Begin tests
#--------------------------------------------------------------------------#

require_ok( "CPAN::Reporter" );

for my $case ( @cases ) {
    my $got = CPAN::Reporter::_parse_option( $case->{input} );
    TODO: {
        local $TODO = "Option parsing not implemented";
        is_deeply( $got, $case->{output}, $case->{label} );
    }
}

