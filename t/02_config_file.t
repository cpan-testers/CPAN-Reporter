#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use Config::Tiny;
use IO::Capture::Stdout;
use IO::Capture::Stderr;
use File::Spec;
use File::Temp qw/tempdir/;

plan tests => 30;
#plan 'no_plan';

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $temp_home = tempdir();

my $home_dir = File::Spec->rel2abs( $temp_home );
my $config_dir = File::Spec->catdir( $home_dir, ".cpanreporter" );
my $config_file = File::Spec->catfile( $config_dir, "config.ini" );
my $default_options = {
    email_from => '',
    cc_author => 'fail',
    edit_report => 'ask/no',
    send_report => 'ask/yes',
};
my @additional_prompts = qw/ smtp_server /;

#--------------------------------------------------------------------------#
# Mocking -- override support/system functions
#--------------------------------------------------------------------------#
    
my $stdout = IO::Capture::Stdout->new;
my $stderr = IO::Capture::Stderr->new;

BEGIN {
    $INC{"File/HomeDir.pm"} = 1; # fake load
}

package File::HomeDir;
sub my_documents { return $home_dir };

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

$stderr->start;

is(CPAN::Reporter::_open_config_file(), undef,
    "opening non-existent file returns undef"
);

$stderr->stop;

like( $stderr->read, "/^Couldn't read CPAN::Reporter configuration file/",
    "opening non-existent file gives a warning"
);

my $configuration;
{
    local $ENV{PERL_MM_USE_DEFAULT} = 1;  # use prompt defaults
    $stdout->start;
    ok( $configuration = CPAN::Reporter::configure(),
        "configure() returned true"
    );
    $stdout->stop;
}

my $output_text = join (q{}, $stdout->read);

for my $option ( keys %$default_options, @additional_prompts) {
    like( $output_text, "/$option/",
        "saw '$option' configuration prompt"
    );
}

is( ref $configuration, 'HASH',
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

my $original_mode = (stat $config_file)[2] && 07777;
chmod 0, $config_file;

SKIP:
{
    skip "Couldn't set config file unreadable; skipping related tests", 3
        if -r $config_file;

    {
        local $ENV{PERL_MM_USE_DEFAULT} = 1;  # use prompt defaults
        $stderr->start;
        $stdout->start;
        $configuration = CPAN::Reporter::configure();
        is( $configuration, undef,
            "configure() is undef if file not readable"
        );
        $stdout->stop;
        $stderr->stop;
    }

    like( $stderr->read, "/Couldn't read CPAN::Reporter configuration file/",
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

$original_mode = (stat $config_file)[2] && 07777;
chmod 0444, $config_file;

SKIP:
{
    skip "Couldn't set config file unwritable; skipping related tests", 2
        if -w $config_file;

    {
        local $ENV{PERL_MM_USE_DEFAULT} = 1;  # use prompt defaults
        $stderr->start;
        $stdout->start;
        $configuration = CPAN::Reporter::configure();
        is( $configuration, undef,
            "configure() is undef if file not writeable"
        );
        $stdout->stop;
        $stderr->stop;
    }

    like( $stderr->read, "/Error writing config file/",
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

my $bogus_email = 'johndoe@nowhere.com';
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
    $stderr->start;
    $stdout->start;
    ok( CPAN::Reporter::configure(),
        "configure() ran again successfully"
    );
    $stdout->stop;
    $stderr->stop;
}

$output_text = join (q{}, $stdout->read);

like( $output_text, "/$bogus_email/",
    "pre-existing email address was seen during configuration prompts"
);

like( $output_text, "/$bogus_smtp/",
    "pre-existing smtp server was seen during configuration prompts"
);

like( $output_text, "/debug/",
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

