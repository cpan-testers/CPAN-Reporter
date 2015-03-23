use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;
use Config;
use IO::CaptureOutput;

#--------------------------------------------------------------------------#
# We need Config to be writeable, so modify the tied hash
#--------------------------------------------------------------------------#

use Config;

BEGIN {
    BEGIN { if (not $] < 5.006 ) { warnings->unimport('redefine') } }
    *Config::STORE = sub { $_[0]->{$_[1]} = $_[2] }
}

# For these tests, hide perl_patchlevel so all prompts are tested
local $Config{perl_patchlevel};

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $perl = Probe::Perl->find_perl_interpreter();
$perl = qq{"$perl"};
my $make = $Config{make};

my $mock_dist = t::MockCPANDist->new( 
    pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
    prereq_pm       => {
        requires => { 'File::Spec' => 0 },
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);
    
my $case = {
    label => "t-Fail",
    name => "t-Fail",
    dist => $mock_dist,
    version => 1.23,
    grade => "fail",
    phase => "test",
    command => "$make test",
    will_send => 1,
};

my %prompts = (
    edit_report => "Do you want to review or edit the test report?",
    send_report => "Do you want to send the report?",
    send_duplicates => "This report is identical to a previous one.  Send it anyway?",
);

my %phase_prompts = (
    PL =>   "Do you want to send the PL report?",
    make => "Do you want to send the make/Build report?",
    test => "Do you want to send the test report?",
);

my %phase_cmd = (
    PL => "$perl Makefile.PL",
    make => "$make",
    test => "$make test",
);

#--------------------------------------------------------------------------#
# plan
#--------------------------------------------------------------------------#

# 7
my $config_plus_dispatch = test_fake_config_plan + test_dispatch_plan;

plan tests => 2 + ( scalar keys %prompts ) + $config_plus_dispatch
    + (1 + $config_plus_dispatch) * (scalar keys %phase_prompts);

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');
require_ok('CPAN::Reporter::History');

test_fake_config( 
        edit_report => "ask/no",
        send_report => "ask/yes",
        send_duplicates => "ask/yes",
);

# create a fake result to force send_duplicates prompt
my $dummy_result = CPAN::Reporter::_init_result(
    "test", $mock_dist, "make test", "fake output", 1
);
$dummy_result->{grade} = "fail";
CPAN::Reporter::History::_record_history( $dummy_result );

# capture dispatch output
my ($stdout, $stderr) = test_dispatch( 
    $case, 
    will_send => $case->{will_send},
);

# check output for prompts
for my $p ( keys %prompts ) {
    like( $stdout, "/" . quotemeta($prompts{$p}) . "/m", "prompt for $p" );
}

# check for per-phase prompts 
for my $p ( keys %phase_prompts ) {
    test_fake_config( "send_$p\_report" => "ask/yes" );
    my $prefix = $p eq 'test' ? 't' : $p;
    $case->{name} = "$prefix-Fail";
    $case->{phase} = $p;
    $case->{command} = $phase_cmd{$p};
    ($stdout, $stderr) = test_dispatch( 
        $case, 
        will_send => $case->{will_send},
    );
    like( $stdout, "/" . $phase_prompts{$p} . "/m", 
        "prompt for send_$p\_report" );
}

