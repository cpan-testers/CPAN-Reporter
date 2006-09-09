#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use Test::MockObject;
use Config::Tiny;
use IO::Capture::Stdout;
use IO::Capture::Stderr;
use File::pushd qw/tempd/;
use File::Spec;

#plan tests => 1;
plan 'no_plan';

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $temp_home = tempd; # deletes when out of scope, i.e. end of program

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

Test::MockObject->fake_module( 'File::HomeDir',
    my_documents => sub { return $home_dir },
);

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
# confirm configure() preserves existing
#--------------------------------------------------------------------------#

my $bogus_email = 'johndoe@nowhere.com';
my $bogus_smtp = 'mail.mail.com';

my $tiny = Config::Tiny->read( $config_file );
$tiny->{_}{email_from} = $bogus_email;
$tiny->{_}{smtp_server} = $bogus_smtp;
ok( $tiny->write( $config_file ),
    "updated config file with a new email address and smtp server"
);

{
    local $ENV{PERL_MM_USE_DEFAULT} = 1;  # use prompt defaults
    $stdout->start;
    ok( CPAN::Reporter::configure(),
        "configure() ran again successfully"
    );
    $stdout->stop;
}

$output_text = join (q{}, $stdout->read);

like( $output_text, "/$bogus_email/",
    "pre-existing email address was seen during configuration prompts"
);

like( $output_text, "/$bogus_smtp/",
    "pre-existing smtp server was seen during configuration prompts"
);

is( CPAN::Reporter::_get_config_options()->{email_from}, $bogus_email,
    "updated config file preserved email address"
);

is( CPAN::Reporter::_get_config_options()->{smtp_server}, $bogus_smtp,
    "updated config file preserved smtp server"
);

# XXX todo -- change something in the config file, rerun configure
# and see that it's preserved

# XXX todo -- make config file read-only and confirm warning on write
# in configure
