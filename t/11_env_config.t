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

# protect CPAN::Reporter from itself
local %ENV = %ENV;
delete $ENV{PERL5OPT};

# Entries bracketed with "/" are taken to be a regex; otherwise literal
my @env_vars= qw(
    /PERL/
    /LC_/
    LANG
    LANGUAGE
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

my %special_vars = (
    '$^X' => $^X,
    '$UID/$EUID' => "$< / $>",
    '$GID' => "$(",
    '$EGID' => "$)",
);

if ( $^O eq 'MSWin32' && eval "require Win32" ) {
    my @getosversion = Win32::GetOSVersion();
    my $getosversion = join(", ", @getosversion);
    $special_vars{"Win32::GetOSName"} = Win32::GetOSName();
    $special_vars{"Win32::GetOSVersion"} = $getosversion;
    $special_vars{"Win32::IsAdminUser"} = Win32::IsAdminUser();
}

my @toolchain_modules = qw(
    CPAN
    Module::Build
    ExtUtils::MakeMaker
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
                + 2 * @env_vars_found
                + 2* keys %special_vars;

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
{
  for my $var ( sort @env_vars_found ) {
      my ($name, $value) = ( $got =~ m{^ +(\Q$var\E) = ([^\n]*?)$}ms );
      is( $name, $var,
          "found \$ENV{$var}"
      );
      is( defined $value ? $value : '', defined $ENV{$var} ? $ENV{$var} : '',
          "value of \$ENV{$var} is correct"
      );
  }
}

#--------------------------------------------------------------------------#
# Special Vars
#--------------------------------------------------------------------------#

$got = CPAN::Reporter::_special_vars_report();

for my $var ( sort keys %special_vars ) {
    my ($name, $value) = ( $got =~ m{ +(\Q$var\E) += +([^\n]*?)$}ms );
    is( $name, $var,
        "found special variable $var"
    );
    is( defined $value ? $value : '', 
        defined $special_vars{$var} ? $special_vars{$var} : '',
        "value of $var is correct"
    );
}
