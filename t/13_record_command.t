#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::Helper;
use t::Frontend;
use Config;
use File::Temp ();
use IO::CaptureOutput qw/capture/;
use Probe::Perl ();

#--------------------------------------------------------------------------#
# fixtures
#--------------------------------------------------------------------------#

my $perl = Probe::Perl->find_perl_interpreter();
$perl = qq{"$perl"};

my $quote = $^O eq 'MSWin32' || $^O eq 'MSDOS' ? q{"} : q{'};

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
        label => "Exit with args in shell quotes",
        program => 'print qq{foo $ARGV[0]\n}; exit 0',
        args => "${quote}apples oranges bananas${quote}",
        output => [ "foo apples oranges bananas\n" ],
        exit_code => 0,
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
        program => '$now=time(); 1 while( time() - $now < 60); print qq{foo\n}; exit 0',
        args => '',
        output => [],
        delay => 60,
        timeout => 5,
        exit_code => 9,
    },
    {
        label => "Timeout not reached",
        program => '$now=time(); 1 while( time() - $now < 2); print qq{foo\n}; exit 0',
        args => '',
        output => ["foo\n"],
        delay => 2,
        timeout => 30,
        exit_code => 0,
    },
    {
        label => "Timeout not reached (quoted args)",
        program => '$now=time(); 1 while( time() - $now < 2); print qq{foo $ARGV[0]\n}; exit 0',
        args => "${quote}apples oranges bananas${quote}",
        output => [ "foo apples oranges bananas\n" ],
        delay => 2,
        timeout => 30,
        exit_code => 0,
    },
);

my $tests_per_case = 4;
plan tests => 1 + $tests_per_case * @cases;

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok( "CPAN::Reporter" );

for my $c ( @cases ) {
SKIP: {
    if ( $^O eq 'MSWin32' && $c->{timeout} ) {
        skip "\$ENV{PERL_AUTHOR_TESTING} required for Win32 timeout testing", 
            $tests_per_case
            unless $ENV{PERL_AUTHOR_TESTING};
        eval "use Win32::Job ()";
        skip "Win32::Job needed for timeout testing", $tests_per_case
            if $@;
    }

    my $fh = File::Temp->new() 
        or die "Couldn't create a temporary file: $!\nIs your temp drive full?";
    print {$fh} $c->{program}, "\n";
    $fh->flush;
    my ($output, $exit);
    my ($stdout, $stderr);
    my $start_time = time();
    my $cmd = $perl; 
    warn "# sleeping for timeout test\n" if $c->{timeout};
    eval {
        capture sub {
            ($output, $exit) = CPAN::Reporter::record_command( 
                "$cmd $fh $c->{args}", $c->{timeout}
            );
        }, \$stdout, \$stderr;
    };
    sleep 1; # pad the run time into the next second
    my $run_time = time() - $start_time;
    diag $@ if $@;
    if ( $c->{timeout} ) {
        my ($time_ok, $verb, $range);
        if ( $c->{timeout} < $c->{delay} ) { # if process should time out
            $time_ok = $run_time <= $c->{delay};
            $verb = "stopped";
            $range = sprintf( "timeout (%d) : ran (%d) : sleep (%d)", 
                $c->{timeout}, $run_time, $c->{delay} 
            );
        }
        else { # process should exit before timeout
            $time_ok = $run_time <= $c->{timeout};
            $verb = "didn't stop";
            $range = sprintf( "sleep (%d) : ran (%d) : timeout (%d)", 
                $c->{delay}, $run_time, $c->{timeout} 
            );
        }
        ok( $time_ok, "$c->{label}: timeout $verb process") or diag $range;
    }
    else {
        pass "$c->{label}: No timeout requested";
    }
    like( $stdout, "/" . quotemeta(join(q{},@$output)) . "/", 
        "$c->{label}: captured stdout" 
    );
    is_deeply( $output, $c->{output},  "$c->{label}: output as expected" )
        or diag "STDOUT:\n$stdout\n\nSTDERR:\n$stderr\n";
    is( $exit, $c->{exit_code}, "$c->{label}: exit code correct" ); 
} # SKIP
}
