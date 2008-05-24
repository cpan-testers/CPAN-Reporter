#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;

use Test::More;
use Config::Tiny;
use IO::CaptureOutput qw/capture/;
use File::Basename qw/basename/;
use File::Spec;
use File::Temp qw/tempdir/;
use t::Frontend;
use t::MockHomeDir;

plan tests => 56;
#plan 'no_plan';

#--------------------------------------------------------------------------#
# Fixtures
#--------------------------------------------------------------------------#

my $config_dir = File::Spec->catdir( t::MockHomeDir::home_dir, ".cpanreporter" );
my $config_file = File::Spec->catfile( $config_dir, "config.ini" );
my $default_options = {
    email_from => '',
#    cc_author => 'default:yes pass/na:no',
    edit_report => 'default:ask/no pass/na:no',
    send_report => 'default:ask/yes pass/na:yes',
#    send_duplicates => 'default:no',
};
my @additional_prompts = qw/ smtp_server /;

my ($rc, $stdout, $stderr);


#--------------------------------------------------------------------------#
# Mocking -- override support/system functions
#--------------------------------------------------------------------------#
    

#--------------------------------------------------------------------------#

require_ok('CPAN::Reporter');
require_ok('CPAN::Reporter::Config');

is( CPAN::Reporter::Config::_get_config_dir(), $config_dir,
    "get config dir path"
);

is( CPAN::Reporter::Config::_get_config_file(), $config_file,
    "get config file path"
);

ok( ! -f $config_file,
    "no config file yet"
);

is( capture(sub{CPAN::Reporter::Config::_open_config_file()}, \$stdout, \$stderr),
    undef,
    "opening non-existent file returns undef"
);

like( $stdout, "/couldn't read configuration file/ms",
    "opening non-existent file gives a warning"
);

{
    local $ENV{PERL_MM_USE_DEFAULT} = 1;  # use prompt defaults
    eval {
        ok( $rc = capture(sub{CPAN::Reporter::configure()}, \$stdout, \$stderr),
            "configure() returned true"
        );
    };
    diag "STDOUT:\n$stdout\nSTDERR:$stderr\n" if $@; 
}

for my $option ( keys %$default_options, @additional_prompts) {
    like( $stdout, "/$option/",
        "saw '$option' configuration prompt"
    );
}

is( ref $rc, 'HASH',
    "configure() returned a hash reference"
);

is_deeply( $rc, $default_options,
    "configure return value has expected defaults"
);

ok( -f $config_file,
    "configuration successfully created a config file"
);

my $new_config = Config::Tiny->read( $config_file );
is_deeply( $new_config->{_}, $default_options,
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

    like( $stdout, "/couldn't read configuration file/",
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

    like( $stdout, "/error writing config file/",
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

#--------------------------------------------------------------------------#
# confirm _get_config_options handles bad action pair validation
#--------------------------------------------------------------------------#

SKIP:
{
    skip "Couldn't set config file writable again; skipping additional tests", 4
        if ! -w $config_file;

    my $bogus_email = 'nobody@nowhere.com';
    my $bogus_smtp = 'mail.mail.com';
    my $bogus_debug = 1;

    my $tiny = Config::Tiny->read( $config_file );
    $tiny->{_}{email_from} = $bogus_email;
    $tiny->{_}{cc_author} = "invalid:invalid";

    ok( $tiny->write( $config_file ),
        "updated config file with a bad cc_author setting"
    );

    $tiny = Config::Tiny->read( $config_file );
    my $parsed_config;
    capture sub{         
        $parsed_config = CPAN::Reporter::Config::_get_config_options( $tiny );
    }, \$stdout, \$stderr;

    like( $stdout, "/invalid option 'invalid:invalid' in 'cc_author'. Using default instead./",
        "bad option warning seen"
    );

    is( $parsed_config->{cc_author}, "default:yes pass/na:no",
        "cc_author default returned"
    );

    $tiny = Config::Tiny->read( $config_file );
    is( $tiny->{_}{cc_author}, "invalid:invalid",
        "bad cc_author preserved in config.ini"
    );
    delete $tiny->{_}{cc_author};
    $tiny->write( $config_file );
}

#--------------------------------------------------------------------------#
# Test skipfile validation
#--------------------------------------------------------------------------#

SKIP:
{
    skip "Couldn't set config file writable again; skipping other tests", 11
        if ! -w $config_file;

    for my $skip_type ( qw/ send_skipfile cc_skipfile / ) {
        my $tiny = Config::Tiny->read( $config_file );
        $tiny->{_}{$skip_type} = 'bogus.skipfile';

        ok( $tiny->write( $config_file ),
            "updated config file with a bad $skip_type"
        );

        $tiny = Config::Tiny->read( $config_file );
        my $parsed_config;
        capture sub{         
            $parsed_config = CPAN::Reporter::Config::_get_config_options( $tiny );
        }, \$stdout, \$stderr;

        like( $stdout, "/invalid option 'bogus.skipfile' in '$skip_type'. Using default instead./",
            "bad $skip_type option warning seen"
        );

        is( $parsed_config->{skipfile}, undef,
            "$skip_type default returned"
        );

        $tiny = Config::Tiny->read( $config_file );
        is( $tiny->{_}{$skip_type}, "bogus.skipfile",
            "bogus $skip_type preserved in config.ini"
        );

        my $skipfile = File::Temp->new(
            TEMPLATE => "CPAN-Reporter-testskip-XXXXXXXX",
            DIR => File::Spec->tmpdir(),
        );
        ok( -r $skipfile, "generated a $skip_type in the temp directory" );
        $tiny->{_}{$skip_type} = "$skipfile";
        ok( $tiny->write( $config_file ),
            "updated config file with an absolute $skip_type path"
        );

        $tiny = Config::Tiny->read( $config_file );
        capture sub{         
            $parsed_config = CPAN::Reporter::Config::_get_config_options( $tiny );
        }, \$stdout, \$stderr;

        is( $stdout, q{},
            "absolute $skip_type ok"
        );

        $skipfile = File::Temp->new( 
            TEMPLATE => "CPAN-Reporter-testskip-XXXXXXXX",
            DIR => $config_dir,
        );
        ok( -r $skipfile, "generated a $skip_type in the config directory" );

        my $relative_skipfile = basename($skipfile);
        ok( ! File::Spec->file_name_is_absolute( $relative_skipfile ),
            "generated a relative $skip_type name"
        );
        $tiny->{_}{$skip_type} = $relative_skipfile;
        ok( $tiny->write( $config_file ),
            "updated config file with a relative $skip_type path"
        );

        $tiny = Config::Tiny->read( $config_file );
        capture sub{         
            $parsed_config = CPAN::Reporter::Config::_get_config_options( $tiny );
        }, \$stdout, \$stderr;

        is( $stdout, q{},
            "relative $skip_type ok"
        );

        delete $tiny->{_}{$skip_type};
        $tiny->write( $config_file );
    }
}


