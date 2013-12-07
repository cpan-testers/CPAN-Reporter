use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;
use IO::CaptureOutput;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
    prereq_pm       => {
        requires => { 'File::Spec' => 0 },
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);
    
my @cases = (
  {
    label => "Build -j2",
    phase => "make",
    command => "Build -j2",
    output => "Output from './Build -j2'\n",
    exit_value => 1 << 8,
    result => {
      grade => "unknown"
    },
    after => {
      grade => "discard",
      grade_msg => "-j is not a valid option for Module::Build (upgrade your CPAN.pm)"
    }
  },
  {
    label => "Build -j3",
    phase => "make",
    command => "Build -j3",
    output => "Output from './Build -j3'\n",
    exit_value => 1 << 8,
    result => {
      grade => "unknown"
    },
    after => {
      grade => "discard",
      grade_msg => "-j is not a valid option for Module::Build (upgrade your CPAN.pm)"
    }
  },
  {
    label => "makefile out of date",
    phase => "make",
    command => "make",
    output => "blah blah\nMakefile out-of-date with respect to Makefile.PL\nblah blah\n",
    exit_value => 1 << 8,
    result => {
      grade => "unknown"
    },
    after => {
      grade => "discard",
      grade_msg => "Makefile out-of-date",
    }
  },
);

#--------------------------------------------------------------------------#
# plan
#--------------------------------------------------------------------------#

plan tests => 2 + test_fake_config_plan() + 2 * @cases;

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');
require_ok('CPAN::Reporter::History');

test_fake_config();

for my $c ( @cases ) {
  # create a fake result to force send_duplicates prompt
  my $dummy_result = CPAN::Reporter::_init_result(
      $c->{phase}, $mock_dist, $c->{command}, $c->{output}, $c->{exit_value},
  );
  $dummy_result->{grade} = $c->{result}{grade};
  $dummy_result->{grade_msg} = "test message";
  CPAN::Reporter::_downgrade_known_causes( $dummy_result );
  is( $dummy_result->{grade}, $c->{after}{grade}, 
    "$c->{label}: grade is '$c->{after}{grade}'"
  );
  is( $dummy_result->{grade_msg}, $c->{after}{grade_msg}, 
    "$c->{label}: grade_msg is correct"
  );
}


