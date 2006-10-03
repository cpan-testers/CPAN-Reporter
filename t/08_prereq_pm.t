#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;

my @prereq_cases = (
    {
        label => "No prereqs",
        prereq_pm => { },
        expect => [
            '/^\s+No requirements found/ims',
        ],
    },
    {
        label => "1 prereq",
        prereq_pm => {
            'File::Spec' => 0
        },
        expect => [
            '/^\s+File::Spec\s+0\s+(\d|\.)+/ims',
        ],
    },
    {
        label => "1 requires",
        prereq_pm => {
            requires => {
                'File::Spec' => 0
            },
            build_requires => {},
        },
        expect => [
            '/^requires:/ims',
            '/^\s+File::Spec\s+0\s+(\d|\.)+/ims',
        ],
    },
    {
        label => "1 build_requires",
        prereq_pm => {
            requires => {},
            build_requires => {
                'File::Spec' => 0
            },
        },
        expect => [
            '/^build_requires:/ims',
            '/^\s+File::Spec\s+0\s+(\d|\.)+/ims',
        ],
    },
);

my $case_count;
for my $case ( @prereq_cases ) {
    $case_count += @{$case->{expect}};
}
plan tests => 1 + test_fake_config_plan() + $case_count;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my @mock_defaults = (
    pretty_id => "Bogus::Module",
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

test_fake_config();

for my $case ( @prereq_cases ) {
    my ($label, $prereq) = map { $case->{$_} } qw/label prereq_pm/;
    my @expects = @{$case->{expect}};
    my $mock_dist = t::MockCPANDist->new( 
        @mock_defaults,
        prereq_pm => $prereq
    );
    my $got = CPAN::Reporter::_prereq_report( $mock_dist );
    like( $got, $_, "$label: $_" ) for @expects;
} 
