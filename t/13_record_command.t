#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use File::Temp ();
use IO::CaptureOutput qw/capture/;
use Probe::Perl ();

#--------------------------------------------------------------------------#
# Test planning
#--------------------------------------------------------------------------#

my @cases = (
    {
        label => "Normal exit",
        program => 'print qq{foo\n}; exit 0',
        output => [ "foo\n" ],
        exit_code => 0,
    }
);

my $tests_per_case = 2;
plan tests => 1 + $tests_per_case * @cases;

#--------------------------------------------------------------------------#
# fixtures
#--------------------------------------------------------------------------#

my $perl = Probe::Perl->find_perl_interpreter();

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok( "CPAN::Reporter" );

for my $c ( @cases ) {
    my $fh = File::Temp->new();
    print {$fh} $c->{program}, "\n";
    $fh->flush;
    my ($output, $exit);
    capture {
        ($output, $exit) = CPAN::Reporter::record_command( "$perl $fh" );
    };
    is_deeply( $output, $c->{output},  "$c->{label}: output correct" );
    is( $exit, $c->{exit_code}, "$c->{label}: exit code correct" ); 
}
