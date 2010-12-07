use strict;
package CPAN::Reporter::PrereqCheck;
# ABSTRACT: Modulino for prerequisite tests

use ExtUtils::MakeMaker 6.36;
use File::Spec;
use CPAN::Version;

my %substitute = (
  'Module::Install' => 'inc::Module::Install',
);

_run() if ! caller();

sub _run {
    my %saw_mod;
    # read module and prereq string from STDIN
    local *DEVNULL;
    open DEVNULL, ">" . File::Spec->devnull;
    while ( <> ) {
        m/^(\S+)\s+([^\n]*)/;
        my ($mod, $need) = ($1, $2);
        die "Couldn't read module for '$_'" unless $mod;
        $need = 0 if not defined $need;

        # handle any odd cases
        my $testmod = $substitute{$mod} || $mod;

        # only evaluate a module once
        next if $saw_mod{$testmod}++;

        # get installed version from file with EU::MM
        my($have, $inst_file, $dir, @packpath);
        if ( $testmod eq "perl" ) {
            $have = $];
        }
        else {
            @packpath = split( /::/, $testmod );
            $packpath[-1] .= ".pm";
            if (@packpath == 1 && $packpath[0] eq "readline.pm") {
                unshift @packpath, "Term", "ReadLine"; # historical reasons
            }
            INCDIR:
            foreach my $dir (@INC) {
                my $pmfile = File::Spec->catfile($dir,@packpath);
                if (-f $pmfile){
                    $inst_file = $pmfile;
                    last INCDIR;
                }
            }

            # get version from file or else report missing
            if ( defined $inst_file ) {
                $have = MM->parse_version($inst_file);
                $have = "0" if ! defined $have || $have eq 'undef';
                # report broken if it can't be loaded
                # "select" to try to suppress spurious newlines
                select DEVNULL; ## no critic
                if ( ! eval "use $testmod (); 1" ) {
                    select STDOUT; ## no critic
                    print "$mod 0 broken\n";
                    next;
                }
                select STDOUT; ## no critic
            }
            else {
                print "$mod 0 n/a\n";
                next;
            }
        }

        # complex requirements are comma separated
        my ( @requirements ) = split /\s*,\s*/, $need;

        my $passes = 0;
        RQ:
        for my $rq (@requirements) {
            if ($rq =~ s|>=\s*||) {
                # no-op -- just trimmed string
            } elsif ($rq =~ s|>\s*||) {
                if (CPAN::Version->vgt($have,$rq)){
                    $passes++;
                }
                next RQ;
            } elsif ($rq =~ s|!=\s*||) {
                if (CPAN::Version->vcmp($have,$rq)) {
                    $passes++; # didn't match
                }
                next RQ;
            } elsif ($rq =~ s|<=\s*||) {
                if (! CPAN::Version->vgt($have,$rq)){
                    $passes++;
                }
                next RQ;
            } elsif ($rq =~ s|<\s*||) {
                if (CPAN::Version->vlt($have,$rq)){
                    $passes++;
                }
                next RQ;
            }
            # if made it here, then it's a normal >= comparison
            if (! CPAN::Version->vlt($have, $rq)){
                $passes++;
            }
        }
        my $ok = $passes == @requirements ? 1 : 0;
        print "$mod $ok $have\n"
    }
    return;
}

1;

__END__

=begin wikidoc

= SYNOPSIS

 require CPAN::Reporter::PrereqCheck;
 my $prereq_check = $INC{'CPAN/Reporter/PrereqCheck.pm'};
 my $result = qx/$perl $prereq_check < $prereq_file/;

= DESCRIPTION

This modulino determines whether a list of prerequisite modules are
available and, if so, their version number.  It is designed to be run
as a script in order to provide this information from the perspective of
a subprocess, just like CPAN::Reporter's invocation of {perl Makefile.PL}
and so on.

It reads a module name and prerequisite string pair from each line of input
and prints out the module name, 0 or 1 depending on whether the prerequisite
is satisifed, and the installed module version.  If the module is not
available, it will print "n/a" for the version.  If the module is available
but can't be loaded, it will print "broken" for the version.  Modules
without a version will be treated as being of version "0".

No user serviceable parts are inside.  This modulino is packaged for
internal use by CPAN::Reporter.

= BUGS

Please report any bugs or feature using the CPAN Request Tracker.
Bugs can be submitted through the web interface at
[http://rt.cpan.org/Dist/Display.html?Queue=CPAN-Reporter]

When submitting a bug or request, please include a test-file or a patch to an
existing test-file that illustrates the bug or desired feature.

= SEE ALSO

* [CPAN::Reporter] -- main documentation

=end wikidoc

=cut
