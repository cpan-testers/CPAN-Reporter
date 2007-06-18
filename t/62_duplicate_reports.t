#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;

#--------------------------------------------------------------------------#
# We need Config to be writeable, so modify the tied hash
#--------------------------------------------------------------------------#

use Config;

BEGIN {
    BEGIN { if (not $] < 5.006 ) { warnings->unimport('redefine') } }
    *Config::STORE = sub { $_[0]->{$_[1]} = $_[2] }
}

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my %mock_dist_info = ( 
    pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
    prereq_pm => {},
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);

my $command = "make test";

my $mock_output = << 'HERE',
t\09_option_parsing....
t\09_option_parsing....NOK 2#   Failed test 'foo'
DIED. FAILED test 2
Failed 1/1 test programs. 1/2 subtests failed.
HERE
    
my @cases = (
    {
        label => "first run",
        send_dup => "no",
        is_dup => 0,
    },
    {
        label => "second run (no duplicates)",
        send_dup => "no",
        is_dup => 1,
    },
    {
        label => "third run (send duplicates)",
        send_dup => "yes",
        is_dup => 1,
    },
    {
        label => "fourth run (with perl_patchlevel)",
        send_dup => "no",
        is_dup => 0,
        patch => 314159,
    },
);

my $expected_history_lines = 0;

for my $c ( @cases ) {
    $expected_history_lines++ if not $c->{is_dup}
}

plan tests => 4 + $expected_history_lines 
                + @cases * ( test_fake_config_plan() + test_dispatch_plan() );

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');
require_ok('Test::Reporter');

my @results;

for my $case ( @cases ) {
    # localize Config in same scope if there is one
    local $Config{perl_patchlevel} = $case->{patch} if $case->{patch};
    # and set it once localized 

    test_fake_config( send_duplicates => $case->{send_dup} );
    $case->{dist} = t::MockCPANDist->new( %mock_dist_info );
    $case->{command} = $command;
    $case->{output} = [ map {$_ . "\n" } 
                        split( "\n", $mock_output) ];
    test_dispatch( 
        $case, 
        will_send => (! $case->{is_dup}) || ( $case->{send_dup} eq 'yes' )
    );
    if ( not $case->{is_dup} ) {
        my $fake_dist = t::MockCPANDist->new( %mock_dist_info );
        my $tr = Test::Reporter->new;
        $tr->distribution( CPAN::Reporter::_format_distname($fake_dist) );
        $tr->grade( 'FAIL' );
        my $line = $tr->subject . " $]";
        $line .= " patch $Config{perl_patchlevel}" 
            if $Config{perl_patchlevel};
        push @results, $line . "\n";
    }
}

#--------------------------------------------------------------------------#
# Check history file format
#--------------------------------------------------------------------------#

my $history_fh = CPAN::Reporter::_open_history_file('<');

ok( $history_fh,
    "Found history file"
);

my @history = <$history_fh>;

is( scalar @history, $expected_history_lines,
    "History file length is $expected_history_lines" 
);

for my $i ( 0 .. $#results ) {
    is( $history[$i], $results[$i],
        "\$history[$i] matched"
    );
}

 


