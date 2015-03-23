use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use t::Frontend;
use Config;
use Probe::Perl;
use File::Temp;

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

# Need to have bleadperls pretend to be normal for these tests
local $Config{perl_patchlevel};

my $make = $Config{make};
my $perl = Probe::Perl->find_perl_interpreter();
$perl = qq{"$perl"};
my $skipfile = File::Temp->new();
print {$skipfile} << 'SKIPFILE';
# comments should be ok
^JOHNDOE
Bogus-SkipModule
SKIPFILE

$skipfile->close;

my %mock_dist_options = (
    prereq_pm       => {
        requires => { 'File::Spec' => 0 },
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);
    
my @cases = (
    {
        label => "dist *not* in",
        pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
        name => "t-Fail",
        version => 1.23,
        grade => "fail",
        phase => "test",
        command => "$perl Makefile.PL",
        will_send => 1,
    },
    {
        label => "dist author in",
        pretty_id => "JOHNDOE/Bogus-Module-1.23.tar.gz",
        name => "t-Fail",
        version => 1.23,
        grade => "fail",
        phase => "test",
        command => "$perl Makefile.PL",
        will_send => 0,
    },
    {
        label => "dist name in",
        pretty_id => "JOHNQP/Bogus-SkipModule-1.23.tar.gz",
        name => "t-Fail",
        version => 1.23,
        grade => "fail",
        phase => "test",
        command => "$perl Makefile.PL",
        will_send => 0,
    },
    {
        label => "dist name in - case insensitive",
        pretty_id => "johnqp/bogus-skipmodule-1.23.tar.gz",
        name => "t-Fail",
        version => 1.23,
        grade => "fail",
        phase => "test",
        command => "$perl Makefile.PL",
        will_send => 0,
    },
);

plan tests => 1 + @cases * (test_fake_config_plan() + test_dispatch_plan());

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

# test send_skipfile
for my $case ( @cases ) {
    local $case->{label} = $case->{label} . " send_skipfile";
    $case->{dist} = t::MockCPANDist->new(
        pretty_id => $case->{pretty_id},
        %mock_dist_options,
    );
    test_fake_config( 
        send_report => "yes",
        send_duplicates => "yes",
        send_skipfile => "$skipfile", 
    );
    test_dispatch( 
        $case, 
        will_send => $case->{will_send},
    );
}

