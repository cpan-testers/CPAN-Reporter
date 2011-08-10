package t::Frontend;
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

use ExtUtils::MakeMaker ();

BEGIN {
    $INC{"CPAN.pm"} = 1; #fake load
    $INC{"Test/Reporter/Transport/Metabase.pm"} = 1; #fake load
    $CPAN::VERSION = 999;
    $Test::Reporter::Transport::Metabase::VERSION = 999;
    $CPAN::Reporter::VERSION ||= 999;
    $CPAN::Reporter::History::VERSION ||= 999;
}

package CPAN::Shell;

sub myprint {
    shift;
    print @_;
}

sub mywarn {
    shift;
    print @_;
}

sub colorable_makemaker_prompt {
    goto \&ExtUtils::MakeMaker::prompt;
}

package CPAN;

$CPAN::Frontend = $CPAN::Frontend = "CPAN::Shell";

1;
