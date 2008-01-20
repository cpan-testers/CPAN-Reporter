use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist qw/bad_author/;
use t::Helper;
use t::Frontend;
use Config;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
    prereq_pm => { 'File::Spec' => 0 },
    # Using MockCPANDist with "bad_author" so the following are ignored
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

my ($got, $prereq_pm);

plan tests => 4 + test_fake_config_plan() + test_report_plan();

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

test_fake_config();

my $result = CPAN::Reporter::_init_result( 
    "test", $mock_dist, "make test", [], 0  
); 
 
is( $result->{author}, "Author",
    "generic author name used"
);

is( $result->{author_id}, q{},
    "author id left blank"
);

my $case = {
    label => "bad author",
    name => "t-Fail",
    phase => "test",
    expected_grade => "fail",
    dist => $mock_dist,
    command => "$Config{make} test"
};

my ($stdout, $stderr) = test_report( $case );

like ($stdout, 
    "/CPAN::Reporter: couldn't determine author_id and won't cc author/ms",
    "Found bad author warning"
);
