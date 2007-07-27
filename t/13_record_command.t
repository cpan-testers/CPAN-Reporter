#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use File::Temp qw/tmpnam/;
use IO::CaptureOutput qw/capture/;
use Probe::Perl ();

#--------------------------------------------------------------------------#
# fixtures
#--------------------------------------------------------------------------#

my $perl = Probe::Perl->find_perl_interpreter();

# set up a temp file for testing command line redirection
my $redirect_file = tmpnam();
END { unlink $redirect_file if -f $redirect_file }

#--------------------------------------------------------------------------#
# Test planning
#--------------------------------------------------------------------------#

my @cases = (
    {
        label => "Exit with 0",
        program => 'print qq{foo\n}; exit 0',
        args => '',
        output => [ "foo\n" ],
        exit_code => 0,
    },
    {
        label => "Exit with 1",
        program => 'print qq{foo\n}; exit 1',
        args => '',
        output => [ "foo\n" ],
        exit_code => 1 << 8,
    },
    {
        label => "Exit with 2",
        program => 'print qq{foo\n}; exit 2',
        args => '',
        output => [ "foo\n" ],
        exit_code => 2 << 8,
    },
    {
        label => "Exit with args and pipe",
        program => 'print qq{foo @ARGV\n}; exit 1',
        args => "bar=1 | $perl -pe 0",
        output => [ "foo bar=1\n" ],
        exit_code => 1 << 8,
    },
);

my $tests_per_case = 3;
plan tests => 1 + $tests_per_case * @cases;

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok( "CPAN::Reporter" );

for my $c ( @cases ) {
    my $fh = File::Temp->new();
    print {$fh} $c->{program}, "\n";
    $fh->flush;
    my ($output, $exit);
    my ($stdout, $stderr);
    capture sub {
        ($output, $exit) = 
            CPAN::Reporter::record_command("$perl $fh $c->{args}" );
    }, \$stdout, \$stderr;
    is_deeply( $output, $c->{output},  "$c->{label}: captured output correct" );
    like( $stdout, "/\Q$c->{output}[0]\E/", "$c->{label}: stdout correct" );
    is( $exit, $c->{exit_code}, "$c->{label}: exit code correct" ); 
}
