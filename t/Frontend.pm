package t::Frontend;
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

use ExtUtils::MakeMaker ();

BEGIN {
    $INC{"CPAN.pm"} = 1; #fake load
}

package CPAN::Shell;

sub myprint {
    shift;
    print @_;
}

sub mywarn {
    shift;
    warn @_;
}

sub colorable_makemaker_prompt {
    goto \&ExtUtils::MakeMaker::prompt;
}

package CPAN;

$CPAN::Frontend = $CPAN::Frontend = "CPAN::Shell";

1;
