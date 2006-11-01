#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use t::MockCPANDist;
use t::Helper;
use Config;

# Entries bracketed with "/" are taken to be a regex; otherwise literal
my @env_vars= qw(
    /PERL/
    PATH
    SHELL
    COMSPEC
    TERM
    AUTOMATED_TESTING
    AUTHOR_TESTING
    INCLUDE
    LIB
    LD_LIBRARY_PATH
    PROCESSOR_IDENTIFIER
    NUMBER_OF_PROCESSORS
);

my @env_vars_found;

for my $var ( @env_vars ) {
    if ( $var =~ m{^/(.+)/$} ) {
        push @env_vars_found, grep { /$1/ } keys %ENV; 
    }
    else {
        push @env_vars_found, $var if exists $ENV{$var};
    }
}

my $special_vars = << "HERE";
    Perl: \$^X = $^X
    UID:  \$<  = $<
    EUID: \$>  = $>
    GID:  \$(  = $(
    EGID: \$)  = $)
HERE

# paths
#    * cwd
#    * compiler
#    * $Config{make}

# toolchain versions (probably all of Bundle::CPAN)
#    * CPAN
#    * Module::Build
#    * ExtUtils::MakeMaker
#    * version

# special handling
#    * umask
#    * Win32::GetOSVersion() (list context)
#    * Win32::IsAdminUser()
#    * locale -- how do I determine this?
#    * compiler tools versions


# qw() protects from interpolation
my @config_vars = qw(
);

plan tests => 1 + test_fake_config_plan()
                + 2 * @env_vars_found
                + 1 # special vars
            ;

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my ($got, $expect);

#--------------------------------------------------------------------------#
# Begin tests
#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

test_fake_config();

#--------------------------------------------------------------------------#
# ENV testing
#--------------------------------------------------------------------------#

$got = CPAN::Reporter::_env_report();
for my $var ( sort @env_vars_found ) {
    my ($name, $value) = ( $got =~ m{^ +(\Q$var\E) = ([^\n]+?)$}ms );
    is( $name, $var,
        "found \$ENV{$var}"
    );
    is( $value, $ENV{$var},
        "value of \$ENV{$var} is correct"
    );
}

#--------------------------------------------------------------------------#
# Special Vars
#--------------------------------------------------------------------------#

$got = CPAN::Reporter::_special_vars_report();
is( $got, $special_vars,
    "Special variables correct"
);
