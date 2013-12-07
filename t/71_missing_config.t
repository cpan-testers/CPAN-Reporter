#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;
use IO::CaptureOutput qw/capture/;

my @test_distros = (
    # pass
    {
        name => 't-Pass',
        eumm_success => 1,
        eumm_grade => "pass",
        eumm_msg => "All tests successful",
        mb_success => 1,
        mb_grade => "pass",
        mb_msg => "All tests successful",
    },
    {
        name => 't-Fail',
        eumm_success => 0,
        eumm_grade => "fail",
        eumm_msg => "One or more tests failed",
        mb_success => 0,
        mb_grade => "fail",
        mb_msg => "One or more tests failed",
    },
);

plan tests => 1 + test_grade_test_plan() * @test_distros + 3;

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

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

# Config file not created in advance with test_config()

for my $case ( @test_distros ) {
    test_grade_test( $case, $mock_dist );
} 

# Test warning messages

my ($stdout, $stderr);
capture sub {
    CPAN::Reporter::_dispatch_report( {} );
}, \$stdout, \$stderr;

like( $stdout, "/couldn't read configuration file/",
    "config file not found warnings"
);
like( $stdout, "/required 'email_from' option missing an email address/", 
    "email address required warning"
);
like( $stdout, "/report will not be sent/",
    "report not sent notice"
);
