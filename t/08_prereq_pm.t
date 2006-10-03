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
    [ 'Bogus::NoVersion',   0.23,      0,   0   ],
    [ 'perl',               5.00,    $],   1   ],   
);

plan tests => 1 + test_fake_config_plan() + 1 + 4 * @prereq_cases;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my %prereq_pm = map { @{$_}[0,1] } @prereq_cases;

my %expect_regex;

my $term_regex = '\s+(\S+)';
for my $case ( @prereq_cases ) {
    my $terms = $case->[3] ? 3 : 4;
    $expect_regex{$case->[0]} = ( $term_regex x $terms );
}

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
# Old style CPAN prereq_pm
#--------------------------------------------------------------------------#

my $mock_dist = t::MockCPANDist->new( 
    @mock_defaults,
    prereq_pm => { %prereq_pm },
);

$got = CPAN::Reporter::_prereq_report( $mock_dist );
@got = split /\n+/ms, $got;

like( shift( @got), '/^requires:\s*$/ms',
    "'requires' header"
);

# Dump header lines
splice( @got, 0, 2 );

for my $case ( sort { lc $a->[0] cmp lc $b->[0] } @prereq_cases ) {
    my ($exp_module, $exp_need, $exp_have, $exp_ok) = @$case;
    my ($bang, $module, $need, $have);
    my $line = shift(@got);
    if ($exp_ok) {
        ($module, $need, $have) = 
            ( $line =~ /^$expect_regex{$exp_module}\s*$/ms );
    }
    else {
        ($bang, $module, $need, $have) = 
            ( $line =~ /^$expect_regex{$exp_module}\s*$/ms );
    }
    is( $module, $exp_module,
        "found '$exp_module' in report"
    );
    is( $bang, $exp_ok ? undef : '!',
        "'$exp_module' flag correct"
    );
    is( $exp_need, $need,
        "'$exp_module' needed version correct"
    );
    is( $exp_have, $have,
        "'$exp_module' installed version correct"
    );
}

