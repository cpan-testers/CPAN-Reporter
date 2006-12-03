#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use Config::Tiny;
use IO::CaptureOutput qw/capture/;
use File::Spec;
use File::Temp qw/tempdir/;
use t::Frontend;

plan tests => 30;
#plan 'no_plan';

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $temp_home = tempdir( 
    "CPAN-Reporter-testhome-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 
);

my $home_dir = File::Spec->rel2abs( $temp_home );
my $config_dir = File::Spec->catdir( $home_dir, ".cpanreporter" );
my $config_file = File::Spec->catfile( $config_dir, "config.ini" );
my $default_options = {
    email_from => '',
    cc_author => 'default:yes pass:no',
    edit_report => 'default:ask/no pass:no',
    send_report => 'default:ask/yes pass:yes na:no',
};
my @additional_prompts = qw/ smtp_server /;

my ($rc, $stdout, $stderr);

#--------------------------------------------------------------------------#
# Mocking -- override support/system functions
#--------------------------------------------------------------------------#
    

BEGIN {
    $INC{"File/HomeDir.pm"} = 1; # fake load
}

package File::HomeDir;
sub my_documents { return $home_dir };
sub my_data { return $home_dir };
sub my_home { return $home_dir };

package main;

#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');

is( CPAN::Reporter::_get_config_dir(), $config_dir,
    "get config dir path"
);

is( CPAN::Reporter::_get_config_file(), $config_file,
    "get config file path"
);

ok( ! -f $config_file,
    "no config file yet"
);

is( capture(sub{CPAN::Reporter::_open_config_file()}, \$stdout, \$stderr),
    undef,
    "opening non-existent file returns undef"
);

like( $stderr, "/^Couldn't read CPAN::Reporter configuration file/",
    "opening non-existent file gives a warning"
);

{
    local $ENV{PERL_MM_USE_DEFAULT} = 1;  # use prompt defaults
    ok( $rc = capture(sub{CPAN::Reporter::configure()}, \$stdout, \$stderr),
        "configure() returned true"
    );
}

for my $option ( keys %$default_options, @additional_prompts) {
    like( $stdout, "/$option/",
        "saw '$option' configuration prompt"
    );
}

is( ref $rc, 'HASH',
    "configure() returned a hash reference"
);

is_deeply( CPAN::Reporter::_get_config_options(), $default_options,
    "configure return value has expected defaults"
);

ok( -f $config_file,
    "configuration successfully created a config file"
);

is_deeply( CPAN::Reporter::_get_config_options(), $default_options,
    "newly created config file has expected defaults"
);

#--------------------------------------------------------------------------#
# check error handling if not readable
#--------------------------------------------------------------------------#

my $original_mode = (stat $config_file)[2] & 07777;
chmod 0, $config_file ;

SKIP:
{
    skip "Couldn't set config file unreadable; skipping related tests", 2
        if -r $config_file;

    {
        local $ENV{PERL_MM_USE_DEFAULT} = 1;  # use prompt defaults
        is( capture(sub{CPAN::Reporter::configure()}, \$stdout, \$stderr),
            undef,
            "configure() is undef if file not readable"
        );
    }

    like( $stderr, "/Couldn't read CPAN::Reporter configuration file/",
        "opening non-readable file gives a warning"
    );
}

chmod $original_mode, $config_file;
ok( -r $config_file,
    "config file reset to readable"
);

#--------------------------------------------------------------------------#
# check error handling if not writeable 
#--------------------------------------------------------------------------#

chmod 0444, $config_file;

SKIP:
{
    skip "Couldn't set config file unwritable; skipping related tests", 2
        if -w $config_file;

    {
        local $ENV{PERL_MM_USE_DEFAULT} = 1;  # use prompt defaults
        is( capture(sub{CPAN::Reporter::configure()}, \$stdout, \$stderr),
            undef,
            "configure() is undef if file not writeable"
        );
    }

    like( $stderr, "/Error writing config file/",
        "opening non-writeable file gives a warning"
    );
}

chmod $original_mode, $config_file;
ok( -w $config_file,
    "config file reset to writeable"
);

#--------------------------------------------------------------------------#
# confirm configure() preserves existing
#--------------------------------------------------------------------------#

SKIP:
{
    skip "Couldn't set config file writable again; skipping related tests", 8
        if ! -w $config_file;

    my $bogus_email = 'nobody@nowhere.com';
    my $bogus_smtp = 'mail.mail.com';
    my $bogus_debug = 1;

    my $tiny = Config::Tiny->read( $config_file );
    $tiny->{_}{email_from} = $bogus_email;
    $tiny->{_}{smtp_server} = $bogus_smtp;
    $tiny->{_}{debug} = $bogus_debug;

    ok( $tiny->write( $config_file ),
        "updated config file with a new email address and smtp server"
    );

    {
        local $ENV{PERL_MM_USE_DEFAULT} = 1;  # use prompt defaults
        ok( capture(sub{CPAN::Reporter::configure()}, \$stdout, \$stderr),
            "configure() ran again successfully"
        );
    }

    like( $stdout, "/$bogus_email/",
        "pre-existing email address was seen during configuration prompts"
    );

    like( $stdout, "/$bogus_smtp/",
        "pre-existing smtp server was seen during configuration prompts"
    );

    like( $stdout, "/debug/",
        "pre-existing debug prompt was seen during configuration prompts"
    );

    is( $tiny->{_}{email_from}, $bogus_email,
        "updated config file preserved email address"
    );

    is( $tiny->{_}{smtp_server}, $bogus_smtp,
        "updated config file preserved smtp server"
    );

    is( $tiny->{_}{debug}, $bogus_debug,
        "updated config file preserved debug value"
    );
}

