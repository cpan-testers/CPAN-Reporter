#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

use FindBin;
use File::Temp 'tempfile';
use Test::More tests => 1;

use CPAN::Reporter::PrereqCheck ();

{
    my($tmpfh,$tmpfile) = tempfile(UNLINK => 1);
    print $tmpfh <<EOF;
Bogus::ComputedVersion 0 1.00
EOF
    close $tmpfh or die $!;

    local @ARGV = $tmpfile;
    local @INC = (@INC, "$FindBin::RealBin/perl5lib");

    ## open stdout to a variable
    open OLDOUT, ">&", \*STDOUT;
    close STDOUT;
    my $output = '';
    open STDOUT, ">", \$output;

    CPAN::Reporter::PrereqCheck::_run();

    ## put things back
    open STDOUT, ">&", \*OLDOUT;

    is $output, "Bogus::ComputedVersion 1 1.00\n";
}
