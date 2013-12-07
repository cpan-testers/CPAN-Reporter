#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;
use Config;

my @prereq_cases = (
      #module               #need       #have   #ok?
    [ 'Bogus::Found',       1.23,                   3.14,       1 ],
    [ 'Bogus::Shadow',      3.14,                   3.14,       1 ],
    [ 'Bogus::NotFound',    1.49,                   "n/a",      0 ],
    [ 'Bogus::TooOld',      2.72,                   0.01,       0 ],
    [ 'Bogus::NoVersion',   0,                      0,          1 ],
    [ 'Bogus::GTE',         '>= 3.14',              3.14,       1 ],
    [ 'Bogus::GT',          '>3.14',                3.14,       0 ],
    [ 'Bogus::LTE',         '<= 3.15',              3.14,       1 ],
    [ 'Bogus::LT',          '<3.14',                3.14,       0 ],
    [ 'Bogus::Conflict',    '!= 3.14',              3.14,       0 ],
    [ 'Bogus::Complex',     '>= 3, !=3.14, < 4',    3.14,       0 ],
    [ 'Bogus::Broken',      '0',                    'broken',   0 ],
    [ 'perl',               5.00,                   $],         1 ],   
);

my @scenarios = (
    #[ "old CPAN-style", undef ], # undef is signal and helps keep count
    [ "only one", qw/requires/ ],
    [ "only one", qw/build_requires/ ],
    [ "both types", qw/requires build_requires/ ],
);

my $scenario_count;
$scenario_count += @$_ - 1 for @scenarios;

plan tests => 2 + test_fake_config_plan() + 
              $scenario_count * ( 1 + 4 * @prereq_cases );

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my %prereq_pm = map { @{$_}[0,1] } @prereq_cases;

my ($module_width, $prereq_width) = (0,0);
for my $case ( @prereq_cases ) {
    $module_width = length $case->[0] if length $case->[0] > $module_width;
    $prereq_width = length $case->[1] if length $case->[1] > $prereq_width;
}

my $expect_regex = '\s+(!|\s)\s' .
                   '(.{' . $module_width . '})\s' .
                   '(.{' . $prereq_width . '})\s(\S+)';
# \s+         leading spaces
# (!|\s)      capture bang or space
# \s         separator space
# (.{N})       module name
# \s         separator space
# (.{N})       module version needed
# \s         separator space
# (\S+)       module version found


my @mock_defaults = (
    pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

my ($got, @got, $expect);

#--------------------------------------------------------------------------#
# Begin tests
#--------------------------------------------------------------------------#

my $perl5lib = File::Spec->rel2abs( File::Spec->catdir( qw/ t perl5lib / ) );
my $shadowlib = File::Spec->rel2abs( 
    File::Spec->catdir( qw/ t perl5lib-shadow / ) );
local $ENV{PERL5LIB} = join $Config{path_sep}, 
                            $perl5lib, $shadowlib, $ENV{PERL5LIB};

require_ok('CPAN::Reporter');

test_fake_config();

#--------------------------------------------------------------------------#
# Test no prereq
#--------------------------------------------------------------------------#

{
    my $mock_dist = t::MockCPANDist->new( 
        @mock_defaults,
        prereq_pm => { },
    );

    $got = CPAN::Reporter::_prereq_report( $mock_dist );
    like( $got, '/^\s*No requirements found\s*$/ms',
            "No requirements specified message correct"
    );
}

#--------------------------------------------------------------------------#
# Scenario testing
#--------------------------------------------------------------------------#

for my $scene ( @scenarios ) {
    
    my ($label, @keys ) = @$scene;
    
    # initialize -- we need to have both keys for CPAN::Reporter
    # to detect new CPAN style
    my %scenario_prereq = (
        requires => undef,
        build_requires => undef,
    );

    # load up prereqs into one or more keys (new style) or replace
    # %scenario_prereq if old, flat style
    if ( @keys ) {
        if ( defined $keys[0] ) {
            $scenario_prereq{$_} = { %prereq_pm } for @keys;
        }
        else {
            # do it old style, but set up $keys[0] to act like "requires"
            # for analysis of output
            %scenario_prereq = %prereq_pm;
            $keys[0] = 'requires';
        }
    }
    
    my $mock_dist = t::MockCPANDist->new( 
        @mock_defaults,
        prereq_pm => { %scenario_prereq },
    );

    $got = CPAN::Reporter::_prereq_report( $mock_dist );
#    diag $got;
    @got = split /\n+/ms, $got;

    for my $prereq_type ( @keys ) {
        like( shift( @got), '/^' . $prereq_type . ':\s*$/ms',
            "$label: '$prereq_type' header"
        );

        # Dump header lines
        splice( @got, 0, 2 );

        for my $case ( sort { lc $a->[0] cmp lc $b->[0] } @prereq_cases ) {
            my ($exp_module, $exp_need, $exp_have, $exp_ok) = @$case;
            my $line = shift(@got);
            my ($bang, $module, $need, $have) = 
                ( $line =~ /^$expect_regex\s*$/ms );
            # trim trailing spaces from fixed-width captures
            $module =~ s/\s*$//;
            $need =~ s/\s*$//;
            is( $module, $exp_module,
                "$label ($prereq_type): found '$exp_module' in report"
            );
            is( $bang, ($exp_ok ? ' ' : '!'),
                "$label ($prereq_type): '$exp_module' flag correct"
            ) or diag "LINE: $line";
            is( $exp_need, $need,
                "$label ($prereq_type): '$exp_module' needed version correct"
            ) or diag "LINE: $line";
            # Check numerically, too, since version.pm/bleadperl will make 
            # 1.2 into 1.200
            ok( $exp_have eq $have || $exp_have == $have,
                "$label ($prereq_type): '$exp_module' installed version correct"
            ) or diag "LINE: $line";
        }
    }
}
