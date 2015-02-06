#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;

my @load_pairs = (['Module::Install' => 0.90],
                  ['Catalyst::DispatchType::Regex' => 5.90032],
                  ['mylib' => undef],
                  ['Acme::Fake' => undef]);

plan tests => 6 + scalar @load_pairs;

require_ok('CPAN::Reporter::PrereqCheck');

#--------------------------------------------------------------------------#
# _try_load tests
#--------------------------------------------------------------------------#
for my $pair (@load_pairs) {
    my ($mod, $have) = @$pair;
    is(CPAN::Reporter::PrereqCheck::_try_load($mod, $have), 1,
       "_try_load for $mod");
}

$INC{'Catalyst.pm'} = '/fake/path/Catalyst.pm';
is(CPAN::Reporter::PrereqCheck::_try_load('signatures', undef), 1,
   "_try_load for loading_conflicts");
delete $INC{'Catalyst.pm'};

my $try = CPAN::Reporter::PrereqCheck::_try_load('Test::More::Hooks', undef);
$try ||= $@ =~ qr(Can't locate Test/More/Hooks\.pm);

ok($try, "_try_load for load_before");

#--------------------------------------------------------------------------#
# _run tests
#--------------------------------------------------------------------------#

use File::Temp 'tempfile';
my ($tfh, $tfn) = tempfile(UNLINK => 1);
print $tfh <<_INPUT_;
Completely::Bogus 0
Test::More 0,>=1,>2,<=3,<4,!=5
Test::More 0
perl
_INPUT_
close $tfh;

push @ARGV, $tfn;  ## _run() uses <>; I tried writing to an in-memory
                   ## variable first, but Devel::Cover reopens STDIN,
                   ## which defeated the purpose of the test

## open stdout to a variable
open OLDOUT, ">&", \*STDOUT;
close STDOUT;
my $output = '';
open STDOUT, ">", \$output;

CPAN::Reporter::PrereqCheck::_run();

## put things back
open STDOUT, ">&", \*OLDOUT;

like($output, qr(Completely::Bogus 0 n/a), "file is not installed");
like($output, qr(Test::More \d \d), "module found");
like($output, qr(perl 1 $]), "perl checked");

exit;
