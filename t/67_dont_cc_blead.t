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

my %mock_dist_options = (
    prereq_pm       => {
        'File::Spec' => 0,
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);
    
my @cases = (
    {
        label => "author cc'd on regular perl",
        pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
        name => "t-Fail",
        version => 1.23,
        grade => "fail",
        phase => "test",
        command => "$perl Makefile.PL",
        will_send => 1,
    },
    {
        label => "no cc on bleadperl",
        pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
        name => "t-Fail",
        version => 1.23,
        grade => "fail",
        phase => "test",
        command => "$perl Makefile.PL",
        will_send => 1,
        patch => 12345,
    },
);

plan tests => 1 + @cases * (1 + test_fake_config_plan() + test_dispatch_plan());

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

# test send_skipfile
for my $case ( @cases ) {
    # override this -- if we're on blead we need to turn it off anyway
    local $Config{perl_patchlevel} = $case->{patch} ? $case->{patch} : q{};
    $case->{dist} = t::MockCPANDist->new(
        pretty_id => $case->{pretty_id},
        %mock_dist_options,
    );
    test_fake_config( 
        send_report => "yes",
        send_duplicates => "yes",
    );
    test_dispatch( 
        $case, 
        will_send => $case->{will_send},
    );
    ok( scalar @t::Helper::cc_list == ( $case->{patch} ? 0 : 1 ),
        "$case->{label}: cc list contents"
    ) or diag "cc list: @t::Helper::cc_list";
}

