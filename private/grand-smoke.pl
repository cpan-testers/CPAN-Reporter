#!/usr/bin/env perl
#
# Runs CPAN::Reporter tests under Makefile.PL and Build.PL

use strict;
use warnings;
use Getopt::Lucid qw( :all );
use IO::CaptureOutput qw( qxx qxy capture );
use Perl6::Say qw/say/;
sub exit_with_usage {
    print STDERR << "USAGE";

Usage: $0 [OPTIONS] <list of perl binaries>

OPTIONS: (at least one of -m or -b is required)

    --makefile, -m      run tests via Makefile.PL
    --build, -b         run tests via Build.PL
    --help, -h          show these instructions
USAGE
exit 1;

}

my $opt = Getopt::Lucid->getopt([
    Switch("help|h"),
    Switch("makefile|m"),
    Switch("build|b"),
]);

if ( $opt->get_help || !($opt->get_makefile || $opt->get_build) || !@ARGV) {
    exit_with_usage() 
}

my @results;
for my $perl ( @ARGV ) {
    check_perl( $perl ) or next;
    push @results, test_makefile( $perl ) if $opt->get_makefile;
    push @results, test_build( $perl ) if $opt->get_build;
}

require Test::More;
Test::More::plan( tests => scalar @results);

for my $r ( @results ) {
    my ($name, $result, $output) = @$r;
    Test::More::ok( $result, $name ) or Test::More::diag( $output );
}

exit;

#--------------------------------------------------------------------------#
# helper subroutines
#--------------------------------------------------------------------------#


sub check_perl {
    my ($perl) = @_;
    my $check_perl = qxx($perl, '-V');
    my $perl_ok = ($check_perl =~ m{^Summary of my perl5}ms);
    if ( ! $perl_ok ) {
        say "'$perl' doesn't seem to be a perl binary -- skipping it.";
    }
    return $perl_ok;
}

sub test_makefile {
    my ($perl) = @_;
    my $name = "Makefile.PL and '$perl'";
    my $output;
    say "* Testing with $name ...";

    # Makefile.PL
    $output = qxy($perl, 'Makefile.PL');
    if ( $? ) {
        return [ $name, 0, $output ];
    }

    # make test
    $output = qxy(qw/make test/);
    if ( $? ) {
        return [ $name, 0, $output ];
    }
    else {
        return [ $name, 1, $output ];
    }
}

sub test_build {
    my ($perl) = @_;
    my $name = "Build.PL and '$perl'";
    my $output;
    say "* Testing with $name ...";

    # Build.PL
    $output = qxy($perl, 'Build.PL');
    if ( $? ) {
        return [ $name, 0, $output ];
    }

    # Build test
    $output = qxy(qw/Build test/);
    if ( $? ) {
        return [ $name, 0, $output ];
    }
    else {
        return [ $name, 1, $output ];
    }
}




