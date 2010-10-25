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
# Skip on Win32 except for release testing
#--------------------------------------------------------------------------#

if ( $^O eq "MSWin32" ) {
    plan skip_all => "\$ENV{RELEASE_TESTING} required for Win32 timeout testing", 
        unless $ENV{RELEASE_TESTING};
    eval "use Win32::Job ()";
    plan skip_all => "Can't interrupt hung processes without Win32::Job"
        if $@;
}

#--------------------------------------------------------------------------#
# fixtures
#--------------------------------------------------------------------------#

my $perl = Probe::Perl->find_perl_interpreter();

my $quote = $^O eq 'MSWin32' || $^O eq 'MSDOS' ? q{"} : q{'};

#--------------------------------------------------------------------------#
# Test planning
#--------------------------------------------------------------------------#

my @cases = (
    {
        label => "regular < global < delay",
        program => '$now=time(); 1 while( time() - $now < 60); print qq{foo\n}; exit 0',
        output => [],
        timeout => 5,
        command_timeout => 30,
        delay => 60,
        exit_code => 9,
    },
    {
        label => "regular < delay < global",
        program => '$now=time(); 1 while( time() - $now < 30); print qq{foo\n}; exit 0',
        output => [],
        timeout => 5,
        delay => 30,
        command_timeout => 60,
        exit_code => 9,
    },
    {
        label => "global < regular < delay",
        program => '$now=time(); 1 while( time() - $now < 60); print qq{foo\n}; exit 0',
        output => [],
        command_timeout => 2,
        timeout => 5,
        delay => 60,
        exit_code => 9,
    },
    {
        label => "global < delay < regular",
        program => '$now=time(); 1 while( time() - $now < 5); print qq{foo\n}; exit 0',
        output => ["foo\n"],
        command_timeout => 2,
        delay => 5,
        timeout => 60,
        exit_code => 0,
    },
    {
        label => "delay < regular < global",
        program => '$now=time(); 1 while( time() - $now < 2); print qq{foo\n}; exit 0',
        output => ["foo\n"],
        delay => 2,
        timeout => 30,
        command_timeout => 60,
        exit_code => 0,
    },
    {
        label => "delay < global < regular",
        program => '$now=time(); 1 while( time() - $now < 2); print qq{foo\n}; exit 0',
        output => ["foo\n"],
        delay => 2,
        command_timeout => 30,
        timeout => 60,
        exit_code => 0,
    },
    {
        label => "global < delay",
        program => '$now=time(); 1 while( time() - $now < 30); print qq{foo\n}; exit 0',
        output => [],
        command_timeout => 5,
        delay => 30,
        exit_code => 9,
    },
    {
        label => "delay < global",
        program => '$now=time(); 1 while( time() - $now < 2); print qq{foo\n}; exit 0',
        output => ["foo\n"],
        delay => 2,
        command_timeout => 30,
        exit_code => 0,
    },
);

my $tests_per_case = 4 + test_fake_config_plan();
plan tests => 1 + $tests_per_case * @cases;

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok( "CPAN::Reporter" );

for my $c ( @cases ) {
SKIP: {
    skip "Couldn't run perl with relative path", $tests_per_case
        if $c->{relative} && system("perl -e 1") == -1;

    my @extra_config = $c->{command_timeout} 
                     ? ( command_timeout => $c->{command_timeout} ) : ();
    test_fake_config( @extra_config );

    my $fh = File::Temp->new( UNLINK => ! $ENV{PERL_CR_NO_CLEANUP} )
        or die "Couldn't create a temporary file: $!\nIs your temp drive full?";
    print {$fh} $c->{program}, "\n";
    $fh->flush;
    my ($output, $exit);
    my ($stdout, $stderr);
    my $start_time = time();
    my $cmd = $c->{relative} ? "perl" : $perl; 
    $cmd .= " $fh";
    warn "# sleeping for timeout test\n" if $c->{delay};
    eval {
        capture sub {
            ($output, $exit) = CPAN::Reporter::record_command( 
                $cmd, $c->{timeout}
            );
        }, \$stdout, \$stderr;
    };
    sleep 1; # pad the run time into the next second
    my $run_time = time() - $start_time;
    diag $@ if $@;
    my ($time_ok, $who, $diag);
    if ( $c->{timeout} ) {
        # (A) program delay, (B) regular timeout, (C) command timeout
        # ABC, ACB, BAC, BCA, CAB, CBA
        # Option 1 -- program ends before either timeout (ABC, ACB)
        if (    $c->{delay} < $c->{command_timeout}
            &&  $c->{delay} < $c->{timeout}
        ) {
            my ($next_t) = sort {$a <=> $b} ($c->{timeout}, $c->{command_timeout});
            $time_ok = $run_time < $next_t;
            $who = "no";
        }
        # Option 2 -- regular before program or command (BAC, BCA)
        elsif ( $c->{timeout} < $c->{command_timeout} 
            &&  $c->{timeout} < $c->{delay}
        ) {
            my ($next_t) = sort {$a <=> $b} ($c->{delay},$c->{command_timeout});
            $time_ok = $run_time < $next_t;
            $who = "regular";
        }
        # Option 3 -- command before program or regular (CAB, CBA)
        # C does nothing so are A,B in right order?
        else {
            # command timeout should be the default
            if ( $c->{timeout} < $c->{delay} ) {
                # did command timeout kill?
                $time_ok = $run_time < $c->{delay};
                $who = "regular"
            }
            else {
                # did no timeout happen
                $time_ok = $run_time < $c->{timeout};
                $who = "no"
            }
        }
        $diag = sprintf( 
            "timeout (%d) : command_timeout (%d) : ran (%d) : sleep (%d)", 
            $c->{timeout}, $c->{command_timeout}, $run_time, $c->{delay} 
        );
    }
    else {
        # command timeout should be the default
        $diag = sprintf( "timeout (%d) : ran (%d) : sleep (%d)", 
            $c->{command_timeout}, $run_time, $c->{delay} 
        );
        if ( $c->{command_timeout} < $c->{delay} ) {
            # did command timeout kill?
            $time_ok = $run_time < $c->{delay};
            $who = "command"
        }
        else {
            # did no timeout happen
            $time_ok = $run_time < $c->{command_timeout};
            $who = "no"
        }
    }

    ok( $time_ok, "$c->{label}: $who timeout") or diag $diag;
    like( $stdout, "/" . quotemeta(join(q{},@{ $output || [] })) . "/", 
        "$c->{label}: captured stdout" 
    );
    is_deeply( $output, $c->{output},  "$c->{label}: output as expected" )
        or diag "STDOUT:\n$stdout\n\nSTDERR:\n$stderr\n";
    is( $exit, $c->{exit_code}, "$c->{label}: exit code correct" ); 
} # SKIP
}
