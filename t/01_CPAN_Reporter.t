# CPAN::Reporter tests
use strict;
use warnings;
use File::Spec;
use File::Temp;
use Probe::Perl;
use Test::More;

#--------------------------------------------------------------------------#
# autoflush to keep output in order
#--------------------------------------------------------------------------#

my $stdout = select(STDERR);
$|++;
select($stdout);
$|++;

#--------------------------------------------------------------------------#
# declarations
#--------------------------------------------------------------------------#

my $perl = Probe::Perl->find_perl_interpreter;
my $pass_pl = File::Spec->catfile(qw/ t pass.pl /);
my $got;

#--------------------------------------------------------------------------#

plan 'no_plan'; #tests =>  2 ;

require_ok( 'CPAN' );
require_ok( 'CPAN::Reporter' );

$CPAN::Be_Silent = 1 unless $CPAN::Be_Silent; # stop 'used once' warnings

can_ok( 'CPAN::Reporter', 'test' );

