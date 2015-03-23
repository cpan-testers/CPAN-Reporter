use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use IO::CaptureOutput qw/capture/;
use File::Spec::Functions qw/catdir catfile rel2abs/;
use t::Frontend;
use t::MockHomeDir;
use Probe::Perl ();

# protect CPAN::Reporter from itself
local %ENV = %ENV;
delete $ENV{PERL5OPT};

my @cases = (
  [ 'Makefile.PL'     , 1 ],
  [ 'NotMakefile.PL'  , 0 ],
  [ 'Build.PL'     , 1 ],
  [ 'NotBuild.PL'  , 0 ],
);

plan tests => 1 + @cases;

#--------------------------------------------------------------------------#
# fixtures
#--------------------------------------------------------------------------#

my $perl = Probe::Perl->find_perl_interpreter();
$perl = qq{"$perl"};

my ($stdout, $stderr, $output, $exit, $line);

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#


require_ok( "CPAN::Reporter" );

for my $c ( @cases ) {
  my ($name, $expect) = @$c;
  my $bin = catfile( qw/t bin /, $name );

  eval {
    capture sub {
      ($output, $exit) = CPAN::Reporter::record_command( "$perl $bin" );
    }, \$stdout, \$stderr;
  };

  chomp( $line = $output->[0] );
  is( $line, $expect, "$name had \$| = $expect" ) or diag $stdout;
}

