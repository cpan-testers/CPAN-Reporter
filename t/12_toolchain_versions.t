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

my @toolchain= qw(
    CPAN
    Cwd
    ExtUtils::CBuilder
    ExtUtils::Command
    ExtUtils::Install
    ExtUtils::MakeMaker
    ExtUtils::Manifest
    ExtUtils::ParseXS
    File::Spec
    Module::Build
    Module::Signature
    Test::Harness
    Test::More
    version
);

# paths
#    * cwd
#    * compiler
#    * $Config{make}

# special handling
#    * umask
#    * locale -- how do I determine this?
#    * compiler tools versions

plan tests => 1 + test_fake_config_plan()
                + 2 * @toolchain ;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my ($got, $expect);

#--------------------------------------------------------------------------#
# Begin tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

test_fake_config();

$got = CPAN::Reporter::_toolchain_report();
$got =~ s{[^\n]+?\n[^\n]+?\n}{}; # eat headers

my %parse = split " ", $got;

my $modules = CPAN::Reporter::_version_finder( map { $_ => 0 } @toolchain );

for my $var ( sort @toolchain ) {
    my $mod_name = quotemeta($var);
    ok( exists $parse{$var},
        "found toolchain module entry for '$var'"
    );
    is( $parse{$var}, $modules->{$var}{have},
        "version of '$var' is correct"
    );
}

