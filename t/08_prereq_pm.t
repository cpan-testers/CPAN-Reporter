#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use Config;

my @prereq_cases = (
      #module               #need   #have   #ok?
    [ 'Bogus::Found',       1.23,   3.14,   1   ],
    [ 'Bogus::NotFound',    1.49,   "n/a",  0   ],
    [ 'Bogus::TooOld',      2.72,   0.01,   0   ],
    [ 'Bogus::NoVersion',      0,      0,   1   ],
    [ 'perl',               5.00,    $],   1   ],   
);

my @scenarios = (
    [ "old CPAN-style", undef ], # undef is signal and helps keep count
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

my $expect_regex = '\s+(!|\s)\s+(\S+)\s+(\S+)\s+(\S+)';
# \s+         leading spaces
# (!|\s)      capture bang or space
# \s+         separator spaces
# (\S+)       module name
# \s+         separator spaces
# (\S+)       module version needed
# \s+         separator spaces
# (\S+)       module version found


my @mock_defaults = (
    pretty_id => "Bogus::Module",
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

my ($got, @got, $expect);

#--------------------------------------------------------------------------#
# Begin tests
#--------------------------------------------------------------------------#

my $perl5lib = File::Spec->rel2abs( File::Spec->catdir( qw/ t perl5lib / ) );
local $ENV{PERL5LIB} = join $Config{path_sep}, $perl5lib, $ENV{PERL5LIB};

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
        requires => {},
        build_requires => {},
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
            is( $module, $exp_module,
                "$label ($prereq_type): found '$exp_module' in report"
            );
            is( $bang, ($exp_ok ? ' ' : '!'),
                "$label ($prereq_type): '$exp_module' flag correct"
            );
            is( $exp_need, $need,
                "$label ($prereq_type): '$exp_module' needed version correct"
            );
            # Check numerically, too, since version.pm/bleadperl will make 
            # 1.2 into 1.200
            ok( $exp_have eq $have || $exp_have == $have,
                "$label ($prereq_type): '$exp_module' installed version correct"
            );
        }
    }
}
