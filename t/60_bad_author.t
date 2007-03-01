#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use IO::CaptureOutput qw/capture/;
use Test::More;
use t::MockCPANDist qw/bad_author/;
use t::Helper;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "Bogus::Module",
    prereq_pm => { 'File::Spec' => 0 },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

my $command = "make test";

my $report_output =  << 'HERE';
t\01_CPAN_Reporter....ok
All tests successful.
Files=1, Tests=3,  0 wallclock secs ( 0.00 cusr +  0.00 csys =  0.00 CPU)
HERE

my ($got, $prereq_pm);

plan tests => 4 + test_fake_config_plan();

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

test_fake_config();

my $result = {};
$result->{dist} = $mock_dist;
$result->{dist}{prereq_pm} = $result->{prereq_pm};
$result->{command} = $command;
$result->{output} = [ map {$_ . "\n" } 
                    split( "\n", $report_output) ];
$result->{original} = $report_output;

my ($stdout, $stderr);

eval {
    capture sub {
        CPAN::Reporter::_expand_report( $result ); 
    }, \$stdout, \$stderr;
    return 1;
}; 
 
is( $@, q{}, 
    "report for ran without error" 
);

is( $result->{author}, "Author",
    "generic author name used"
);

is( $result->{author_id}, q{},
    "author id left blank"
);


