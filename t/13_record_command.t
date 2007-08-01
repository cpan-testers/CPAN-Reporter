#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::Frontend;
use File::Temp ();
use IO::CaptureOutput qw/capture/;
use Probe::Perl ();

#--------------------------------------------------------------------------#
# fixtures
#--------------------------------------------------------------------------#

my $perl = Probe::Perl->find_perl_interpreter();

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
    {
        label => "Timeout kills process",
        program => '$now=time(); 1 while( time() - $now < 20); print qq{foo\n}; exit 0',
        args => '',
        output => [],
        timeout => 5,
        exit_code => 9,
    },
    {
        label => "Timeout not reached",
        program => '$now=time(); 1 while( time() - $now < 2); print qq{foo\n}; exit 0',
        args => '',
        output => ["foo\n"],
        timeout => 10,
        exit_code => 0,
    },
);

my $tests_per_case = 3;
plan tests => 1 + $tests_per_case * @cases;

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok( "CPAN::Reporter" );

for my $c ( @cases ) {
    my $fh = File::Temp->new() 
        or die "Couldn't create a temporary file: $!\nIs your temp drive full?";
    print {$fh} $c->{program}, "\n";
    $fh->flush;
    my ($output, $exit);
    my ($stdout, $stderr);
    eval {
        capture sub {
            ($output, $exit) = CPAN::Reporter::record_command( 
                "$perl $fh $c->{args}", $c->{timeout}
            );
        }, \$stdout, \$stderr;
    };
    diag $@ if $@;
    like( $stdout, "/" . quotemeta(join(q{},@$output)) . "/", 
        "$c->{label}: captured stdout" 
    );
    is_deeply( $output, $c->{output},  "$c->{label}: output as expected" )
        or diag "STDOUT:\n$stdout\n\nSTDERR:\n$stderr\n";
    is( $exit, $c->{exit_code}, "$c->{label}: exit code correct" ); 
}
