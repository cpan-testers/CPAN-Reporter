#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;
use Probe::Perl;

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

my $make = $Config{make};
my $perl = Probe::Perl->find_perl_interpreter();
$perl = qq{"$perl"};

my %mock_dist_info = ( 
    prereq_pm       => {
        requires => { 'File::Spec' => 0 },
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);
    
my @cases = (
    {
        label => "first PL failure",
        name => "PL-Fail",
        version => 1.23,
        grade => "unknown",
        phase => "PL",
        command => "$perl Makefile.PL",
        send_dup => "no",
        is_dup => 0,
    },
    {
        label => "second PL failure",
        name => "PL-Fail",
        version => 1.23,
        grade => "unknown",
        phase => "PL",
        command => "$perl Makefile.PL",
        send_dup => "no",
        is_dup => 1,
    },
    {
        label => "first PL unsupported",
        name => "PL-NoSupport",
        version => 1.23,
        grade => "na",
        phase => "PL",
        command => "$perl Makefile.PL",
        send_dup => "no",
        is_dup => 0,
    },
    {
        label => "first make failure",
        name => "make-Fail",
        version => 1.23,
        grade => "unknown",
        phase => "make",
        command => "$make",
        send_dup => "no",
        is_dup => 0,
    },
    {
        label => "second make failure",
        name => "make-Fail",
        version => 1.23,
        grade => "unknown",
        phase => "make",
        command => "$make",
        send_dup => "no",
        is_dup => 1,
    },
    {
        label => "first test unknown",
        name => "NoTestFiles",
        version => 1.23,
        grade => "unknown",
        phase => "test",
        command => "$make test",
        send_dup => "no",
        is_dup => 0,
    },
    {
        label => "first test failure",
        name => "t-Fail",
        version => 1.23,
        grade => "fail",
        phase => "test",
        command => "$make test",
        send_dup => "no",
        is_dup => 0,
    },
    {
        label => "second test failure (but send dup)",
        name => "t-Fail",
        version => 1.23,
        grade => "fail",
        phase => "test",
        command => "$make test",
        send_dup => "yes",
        is_dup => 1,
    },
    {
        label => "first discard",
        name => 't-PrereqMiss',
        version => 9.11,
        prereq => { 'requires' => { 'Bogus::Module::Doesnt::Exist' => 0 } },
        grade => "discard",
        phase => "test",
        command => "$make test",
        send_dup => "no",
        is_dup => 0,
    },
    {
        label => "third test failure (new version)",
        name => "t-Fail",
        version => 1.24,
        grade => "fail",
        phase => "test",
        command => "$make test",
        send_dup => "no",
        is_dup => 0,
    },
    {
        label => "second discard",
        name => 't-PrereqMiss',
        version => 9.11,
        prereq => { 'requires' => { 'Bogus::Module::Doesnt::Exist' => 0 } },
        grade => "discard",
        phase => "test",
        command => "$make test",
        send_dup => "no",
        is_dup => 1,
    },
);

my $expected_history_lines = 1; # opening comment line

for my $c ( @cases ) {
    $expected_history_lines++ if not $c->{is_dup}
}

plan tests => 5 + $expected_history_lines 
                + @cases * ( 3 + test_fake_config_plan() 
                               + test_dispatch_plan() );

#--------------------------------------------------------------------------#
# subs
#--------------------------------------------------------------------------#

sub history_format {
    my ($case) = @_;
    my ($phase, $grade, $dist) = @{$case}{qw/phase grade dist/};
    $grade = uc $grade;
    my $perl_ver = "perl-" . CPAN::Reporter::History::_perl_version(); 
    $perl_ver .= " patch $Config{perl_patchlevel}" if $Config{perl_patchlevel};
    my $arch = "$Config{archname} $Config{osvers}";
    my $dist_name = $dist->base_id;
    return "$phase $grade $dist_name ($perl_ver) $arch\n";
}

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');
require_ok('CPAN::Reporter::History');

my @results;

for my $case ( @cases ) {
    # localize Config in same scope if there is a patchlevel
    local $Config{perl_patchlevel} = $case->{patch} if $case->{patch};
    # and set it once localized 

    test_fake_config( send_duplicates => $case->{send_dup} );
    $case->{dist} = t::MockCPANDist->new( 
        %mock_dist_info,
        pretty_id => "JOHNQP/Bogus-Module-$case->{version}.tar.gz",
    );
    $case->{dist}{prereq_pm} = $case->{prereq} if $case->{prereq};
    test_dispatch( 
        $case, 
        will_send => ($case->{grade} ne 'discard') && 
                     (! $case->{is_dup}) || ( $case->{send_dup} eq 'yes' )
    );
    if ( not $case->{is_dup} ) {
        push @results, history_format($case);
    }
    my @found;
    ok( @found = CPAN::Reporter::History::have_tested(
            dist => $case->{dist}->base_id ),
        "$case->{label}: have_tested( base_id ) is true"
    );
    is( ref($found[0]), 'HASH',
        "$case->{label}: have_tested returns AoH"
    );
    is( $found[0]{dist}, $case->{dist}->base_id,
        "$case->{label}: have_tested struct has dist name"
    ); 

}

#--------------------------------------------------------------------------#
# have_tested fails
#--------------------------------------------------------------------------#

ok( ! CPAN::Reporter::History::have_tested( dist => "AADFASDFADSFASD" ),
    "have_tested() returns false if not found"
);

#--------------------------------------------------------------------------#
# Check history file format
#--------------------------------------------------------------------------#

my $history_fh = CPAN::Reporter::History::_open_history_file('<');

ok( $history_fh,
    "found history file"
);

my @history = <$history_fh>;

is( scalar @history, $expected_history_lines,
    "history file length is $expected_history_lines" 
);

is( shift @history, "# Generated by CPAN::Reporter $CPAN::Reporter::History::VERSION\n",
    "history starts with version comment"
);

for my $i ( 0 .. $#results ) {
    is( $history[$i], $results[$i],
        "history matched results[$i]"
    );
}


