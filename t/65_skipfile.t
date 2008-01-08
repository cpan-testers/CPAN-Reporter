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
# Fixtures
#--------------------------------------------------------------------------#

my $make = $Config{make};
my $perl = Probe::Perl->find_perl_interpreter();
my $skipfile = File::Temp->new();
print {$skipfile} << 'SKIPFILE';
# comments should be ok
^JOHNDOE
Bogus-SkipModule
SKIPFILE

my %mock_dist_options = (
    prereq_pm       => {
        'File::Spec' => 0,
    },
    author_id       => "JOHNQP",
    author_fullname => "John Q. Public",
);
    
my @cases = (
    {
        label => "dist *not* in skipfile",
        pretty_id => "JOHNQP/Bogus-Module-1.23.tar.gz",
        name => "t-fail",
        version => 1.23,
        grade => "fail",
        phase => "test",
        command => "$perl Makefile.PL",
        will_send => 1,
    },
    {
        label => "dist author in skipfile",
        pretty_id => "JOHNDOE/Bogus-Module-1.23.tar.gz",
        name => "t-fail",
        version => 1.23,
        grade => "fail",
        phase => "test",
        command => "$perl Makefile.PL",
        will_send => 0,
    },
    {
        label => "dist name in skipfile",
        pretty_id => "JOHNQP/Bogus-SkipModule-1.23.tar.gz",
        name => "t-fail",
        version => 1.23,
        grade => "fail",
        phase => "test",
        command => "$perl Makefile.PL",
        will_send => 0,
    },
);

plan tests => 1 + @cases * ( test_fake_config_plan() + test_dispatch_plan() );

#--------------------------------------------------------------------------#
# tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

for my $case ( @cases ) {
    $case->{dist} = t::MockCPANDist->new(
        pretty_id => $case->{pretty_id},
        %mock_dist_options,
    );
    test_fake_config( 
        send_report => "yes",
        send_duplicates => "yes",
        skipfile => "$skipfile", 
    );
    test_dispatch( 
        $case, 
        will_send => $case->{will_send},
    );
}

