use strict;
package CPAN::Reporter::Config;

our $VERSION = '1.2015';

use Config::Tiny 2.08 ();
use File::Glob ();
use File::HomeDir 0.58 ();
use File::Path qw/mkpath/;
use File::Spec 3.19 ();
use IPC::Cmd 0.76 ();
use IO::File ();
use CPAN 1.9301 (); # for printing warnings

#--------------------------------------------------------------------------#
# Back-compatibility checks -- just once per load
#--------------------------------------------------------------------------#

# 0.28_51 changed Mac OS X config file location -- if old directory is found,
# move it to the new location
if ( $^O eq 'darwin' ) {
    my $old = File::Spec->catdir(File::HomeDir->my_documents,".cpanreporter");
    my $new = File::Spec->catdir(File::HomeDir->my_home,".cpanreporter");
    if ( ( -d $old ) && (! -d $new ) ) {
        $CPAN::Frontend->mywarn( << "HERE");
CPAN::Reporter: since CPAN::Reporter 0.28_51, the Mac OSX config directory
has changed.

  Old: $old
  New: $new

Your existing configuration file will be moved automatically.
HERE
        mkpath($new);
        my $OLD_CONFIG = IO::File->new(
            File::Spec->catfile($old, "config.ini"), "<"
        ) or die $!;
        my $NEW_CONFIG = IO::File->new(
            File::Spec->catfile($new, "config.ini"), ">"
        ) or die $!;
        $NEW_CONFIG->print( do { local $/; <$OLD_CONFIG> } );
        $OLD_CONFIG->close;
        $NEW_CONFIG->close;
        unlink File::Spec->catfile($old, "config.ini") or die $!;
        rmdir($old) or die $!;
    }
}

#--------------------------------------------------------------------------#
# Public
#--------------------------------------------------------------------------#

sub _configure {
    my $config_dir = _get_config_dir();
    my $config_file = _get_config_file();

    mkpath $config_dir if ! -d $config_dir;
    if ( ! -d $config_dir ) {
        $CPAN::Frontend->myprint(
            "\nCPAN::Reporter: couldn't create configuration directory '$config_dir': $!"
        );
        return;
    }

    my $config;
    my $existing_options;

    # explain grade:action pairs
    $CPAN::Frontend->myprint( _grade_action_prompt() );

    # read or create
    if ( -f $config_file ) {
        $CPAN::Frontend->myprint(
            "\nCPAN::Reporter: found your CPAN::Reporter config file at:\n$config_file\n"
        );
        $config = _open_config_file();
        # if we can't read it, bail out
        if ( ! $config ) {
            $CPAN::Frontend->mywarn("\n
                CPAN::Reporter: configuration will not be changed\n");
            return;
        }
        # clone what's in the config file
        $existing_options = { %{$config->{_}} } if $config;
        $CPAN::Frontend->myprint(
            "\nCPAN::Reporter: Updating your CPAN::Reporter configuration settings:\n"
        );
    }
    else {
        $CPAN::Frontend->myprint(
            "\nCPAN::Reporter: no config file found; creating a new one.\n"
        );
        $config = Config::Tiny->new();
    }

    my %spec = _config_spec();

    for my $k ( _config_order() ) {
        my $option_data = $spec{$k};
        $CPAN::Frontend->myprint( "\n" . $option_data->{info}. "\n");
        # options with defaults are mandatory
        if ( defined $option_data->{default} ) {
            # if we have a default, always show as a sane recommendation
            if ( length $option_data->{default} ) {
                $CPAN::Frontend->myprint(
                    "(Recommended: '$option_data->{default}')\n\n"
                );
            }
            # repeat until validated
            PROMPT:
            while ( defined (
                my $answer = CPAN::Shell::colorable_makemaker_prompt(
                    "$k?",
                    $existing_options->{$k} || $option_data->{default}
                )
            )) {
                if  ( ! $option_data->{validate} ||
                        $option_data->{validate}->($k, $answer, $config->{_})
                    ) {
                    $config->{_}{$k} = $answer;
                    last PROMPT;
                }
            }
        }
        else {
            # only initialize options without default if
            # answer matches non white space and validates,
            # otherwise reset it
            my $answer = CPAN::Shell::colorable_makemaker_prompt(
                "$k?",
                $existing_options->{$k} || q{}
            );
            if ( $answer =~ /\S/ ) {
                $config->{_}{$k} = $answer;
            }
            else {
                delete $config->{_}{$k};
            }
        }
        # delete existing as we proceed so we know what's left
        delete $existing_options->{$k};
    }

    # initialize remaining existing options
    $CPAN::Frontend->myprint(
        "\nYour CPAN::Reporter config file also contains these advanced " .
          "options:\n\n") if keys %$existing_options;
    for my $k ( keys %$existing_options ) {
        $config->{_}{$k} = CPAN::Shell::colorable_makemaker_prompt(
            "$k?", $existing_options->{$k}
        );
    }

    $CPAN::Frontend->myprint(
        "\nCPAN::Reporter: writing config file to '$config_file'.\n"
    );
    if ( $config->write( $config_file ) ) {
        return $config->{_};
    }
    else {
        $CPAN::Frontend->mywarn( "\nCPAN::Reporter: error writing config file to '$config_file':\n"
            .  Config::Tiny->errstr(). "\n");
        return;
    }
}

#--------------------------------------------------------------------------#
# Private
#--------------------------------------------------------------------------#

#--------------------------------------------------------------------------#
# _config_order -- determines order of interactive config.  Only items
# in interactive config will be written to a starter config file
#--------------------------------------------------------------------------#

sub _config_order {
    return qw(
        email_from
        edit_report
        send_report
        transport
    );
}

#--------------------------------------------------------------------------#
# _config_spec -- returns configuration options information
#
# Keys include
#   default     --  recommended value, used in prompts and as a fallback
#                   if an options is not set; mandatory if defined
#   prompt      --  short prompt for EU::MM prompting
#   info        --  long description shown before prompting
#   validate    --  CODE ref; return normalized option or undef if invalid
#--------------------------------------------------------------------------#

my %option_specs = (
    email_from => {
        default => '',
        prompt => 'What email address will be used to reference your reports?',
        info => <<'HERE',
CPAN::Reporter requires a valid email address to identify senders
in the body of a test report.  Please use a standard email format
like: "John Doe" <jdoe@example.com>
HERE
    },
    smtp_server => {
        default => undef, # (deprecated)
        prompt  => "[DEPRECATED] It's safe to remove this from your config file.",
    },
    edit_report => {
        default => 'default:ask/no pass/na:no',
        prompt => "Do you want to review or edit the test report?",
        validate => \&_validate_grade_action_pair,
        info => <<'HERE',
Before test reports are sent, you may want to review or edit the test
report and add additional comments about the result or about your system
or Perl configuration.  By default, CPAN::Reporter will ask after
each report is generated whether or not you would like to edit the
report. This option takes "grade:action" pairs.
HERE
    },
    send_report => {
        default => 'default:ask/yes pass/na:yes',
        prompt => "Do you want to send the report?",
        validate => \&_validate_grade_action_pair,
        info => <<'HERE',
By default, CPAN::Reporter will prompt you for confirmation that
the test report should be sent before actually doing it. This
gives the opportunity to skip sending particular reports if
you need to (e.g. if you caused the failure). This option takes
"grade:action" pairs.
HERE
    },
    transport => {
        default  => 'Metabase uri https://metabase.cpantesters.org/api/v1/ id_file metabase_id.json',
        prompt   => 'Which transport system will be used to transmit the reports?',
        validate => \&_validate_transport,
        info     => <<'HERE',
CPAN::Reporter sends your reports over HTTPS using Metabase. This option lets
you set a different uri, transport mechanism and metabase profile path. If you
are receiving HTTPS errors, you may change the uri to use plain HTTP, though
this is not recommended. Unless you know what you're doing, just accept
the default value.
HERE
    },
    send_duplicates => {
        default => 'default:no',
        prompt => "This report is identical to a previous one.  Send it anyway?",
        validate => \&_validate_grade_action_pair,
        info => <<'HERE',
CPAN::Reporter records tests grades for each distribution, version and
platform.  By default, duplicates of previous results will not be sent at
all, regardless of the value of the "send_report" option.  This option takes
"grade:action" pairs.
HERE
    },
    send_PL_report => {
        prompt => "Do you want to send the PL report?",
        default => undef,
        validate => \&_validate_grade_action_pair,
    },
    send_make_report => {
        prompt => "Do you want to send the make/Build report?",
        default => undef,
        validate => \&_validate_grade_action_pair,
    },
    send_test_report => {
        prompt => "Do you want to send the test report?",
        default => undef,
        validate => \&_validate_grade_action_pair,
    },
    send_skipfile => {
        prompt => "What file has patterns for things that shouldn't be reported?",
        default => undef,
        validate => \&_validate_skipfile,
    },
    cc_skipfile => {
        prompt => "What file has patterns for things that shouldn't CC to authors?",
        default => undef,
        validate => \&_validate_skipfile,
    },
    command_timeout => {
        prompt => "If no timeout is set by CPAN, halt system commands after how many seconds?",
        default => undef,
        validate => \&_validate_seconds,
    },
    email_to => {
        default => undef,
    },
    editor => {
        default => undef,
    },
    debug => {
        default => undef,
    },
    retry_submission => {
        default => undef,
    },
    '_store_problems_in_dir' => { #experimental
        default => undef,
    },
    '_problem_log' => { #experimental
        default => undef,
    },
);

sub _config_spec { return %option_specs }

#--------------------------------------------------------------------------#
# _generate_profile
#
# Run 'metabase-profile' in the .cpanreporter directory
#--------------------------------------------------------------------------#

sub _generate_profile {
    my ($id_file, $config) = @_;

    my $cmd = IPC::Cmd::can_run('metabase-profile');
    return unless $cmd;

    # XXX this is an evil assumption about email addresses, but
    # might do for simple cases that users might actually provide

    my @opts = ("--output" => $id_file);
    my $email = $config->{email_from};

    if ($email =~ /\A(.+)\s+<([^>]+)>\z/ ) {
        push @opts, "--email"   => $2;
        my $name = $1;
        $name =~ s/\A["'](.*)["']\z/$1/;
        push ( @opts, "--name"    => $1)
            if length $name;
    }
    else {
        push @opts, "--email"   => $email;
    }

    # XXX profile 'secret' is really just a generated API key, so we
    # can create something fairly random for the user and use that
    push @opts, "--secret"      => sprintf("%08x", rand(2**31));

    return scalar IPC::Cmd::run(
        command => [ $cmd, @opts ],
        verbose => 1,
    );
}

#--------------------------------------------------------------------------#
# _get_config_dir
#--------------------------------------------------------------------------#

sub _get_config_dir {
    if ( defined $ENV{PERL_CPAN_REPORTER_DIR} &&
         length  $ENV{PERL_CPAN_REPORTER_DIR}
    ) {
        return $ENV{PERL_CPAN_REPORTER_DIR};
    }

    my $conf_dir = File::Spec->catdir(File::HomeDir->my_home, ".cpanreporter");

    if ($^O eq 'MSWin32') {
      my $alt_dir = File::Spec->catdir(File::HomeDir->my_documents, ".cpanreporter");
      $conf_dir = $alt_dir if -d $alt_dir && ! -d $conf_dir;
    }

    return $conf_dir;
}

#--------------------------------------------------------------------------#
# _get_config_file
#--------------------------------------------------------------------------#

sub _get_config_file {
    if (  defined $ENV{PERL_CPAN_REPORTER_CONFIG} &&
          length  $ENV{PERL_CPAN_REPORTER_CONFIG}
    ) {
        return $ENV{PERL_CPAN_REPORTER_CONFIG};
    }
    else {
        return File::Spec->catdir( _get_config_dir, "config.ini" );
    }
}

#--------------------------------------------------------------------------#
# _get_config_options
#--------------------------------------------------------------------------#

sub _get_config_options {
    my $config = shift;
    # extract and return valid options, with fallback to defaults
    my %spec = CPAN::Reporter::Config::_config_spec();
    my %active;
    OPTION: for my $option ( keys %spec ) {
        if ( exists $config->{_}{$option} ) {
            my $val = $config->{_}{$option};
            if  (   $spec{$option}{validate} &&
                    ! $spec{$option}{validate}->($option, $val)
                ) {
                    $CPAN::Frontend->mywarn( "\nCPAN::Reporter: invalid option '$val' in '$option'. Using default instead.\n\n" );
                    $active{$option} = $spec{$option}{default};
                    next OPTION;
            }
            $active{$option} = $val;
        }
        else {
            $active{$option} = $spec{$option}{default}
                if defined $spec{$option}{default};
        }
    }
    return \%active;
}


#--------------------------------------------------------------------------#
# _grade_action_prompt -- describes grade action pairs
#--------------------------------------------------------------------------#

sub _grade_action_prompt {
    return << 'HERE';

Some of the following configuration options require one or more "grade:action"
pairs that determine what grade-specific action to take for that option.
These pairs should be space-separated and are processed left-to-right. See
CPAN::Reporter documentation for more details.

    GRADE   :   ACTION  ======> EXAMPLES
    -------     -------         --------
    pass        yes             default:no
    fail        no              default:yes pass:no
    unknown     ask/no          default:ask/no pass:yes fail:no
    na          ask/yes
    default

HERE
}

#--------------------------------------------------------------------------#
# _is_valid_action
#--------------------------------------------------------------------------#

my @valid_actions = qw{ yes no ask/yes ask/no ask };
sub _is_valid_action {
    my $action = shift;
    return grep { $action eq $_ } @valid_actions;
}

#--------------------------------------------------------------------------#
# _is_valid_grade
#--------------------------------------------------------------------------#

my @valid_grades = qw{ pass fail unknown na default };
sub _is_valid_grade {
    my $grade = shift;
    return grep { $grade eq $_ } @valid_grades;
}


#--------------------------------------------------------------------------#
# _normalize_id_file
#--------------------------------------------------------------------------#

sub _normalize_id_file {
    my ($id_file) = @_;

    # Windows does not use ~ to signify a home directory
    if ( $^O eq 'MSWin32' && $id_file =~ m{^~/(.*)} ) {
        $id_file = File::Spec->catdir(File::HomeDir->my_home, $1);
    }
    elsif ( $id_file =~ /~/ ) {
        $id_file = File::Spec->canonpath(File::Glob::bsd_glob( $id_file ));
    }
    unless ( File::Spec->file_name_is_absolute( $id_file ) ) {
        $id_file = File::Spec->catfile(
            CPAN::Reporter::Config::_get_config_dir(), $id_file
        );
    }
    return $id_file;
}

#--------------------------------------------------------------------------#
# _open_config_file
#--------------------------------------------------------------------------#

sub _open_config_file {
    my $config_file = _get_config_file();
    my $config = Config::Tiny->read( $config_file )
        or $CPAN::Frontend->mywarn("CPAN::Reporter: couldn't read configuration file " .
                "'$config_file': \n" . Config::Tiny->errstr() . "\n");
    return $config;
}

#--------------------------------------------------------------------------#
# _validate
#
# anything is OK if there is no validation subroutine
#--------------------------------------------------------------------------#

sub _validate {
    my ($name, $value) = @_;
    return 1 if ! exists $option_specs{$name}{validate};
    return $option_specs{$name}{validate}->($name, $value);
}

#--------------------------------------------------------------------------#
# _validate_grade_action
# returns hash of grade => action
# returns undef
#--------------------------------------------------------------------------#

sub _validate_grade_action_pair {
    my ($name, $option) = @_;
    $option ||= "no";

    my %ga_map; # grade => action

    PAIR: for my $grade_action ( split q{ }, $option ) {
        my ($grade_list,$action);

        if ( $grade_action =~ m{.:.} ) {
            # parse pair for later check
            ($grade_list, $action) = $grade_action =~ m{\A([^:]+):(.+)\z};
        }
        elsif ( _is_valid_action($grade_action) ) {
            # action by itself
            $ga_map{default} = $grade_action;
            next PAIR;
        }
        elsif ( _is_valid_grade($grade_action) ) {
            # grade by itself
            $ga_map{$grade_action} = "yes";
            next PAIR;
        }
        elsif( $grade_action =~ m{./.} ) {
            # gradelist by itself, so setup for later check
            $grade_list = $grade_action;
            $action = "yes";
        }
        else {
            # something weird, so warn and skip
            $CPAN::Frontend->mywarn(
                "\nCPAN::Reporter: ignoring invalid grade:action '$grade_action' for '$name'.\n\n"
            );
            next PAIR;
        }

        # check gradelist
        my %grades = map { ($_,1) } split( "/", $grade_list);
        for my $g ( keys %grades ) {
            if ( ! _is_valid_grade($g) ) {
                $CPAN::Frontend->mywarn(
                    "\nCPAN::Reporter: ignoring invalid grade '$g' in '$grade_action' for '$name'.\n\n"
                );
                delete $grades{$g};
            }
        }

        # check action
        if ( ! _is_valid_action($action) ) {
            $CPAN::Frontend->mywarn(
                "\nCPAN::Reporter: ignoring invalid action '$action' in '$grade_action' for '$name'.\n\n"
            );
            next PAIR;
        }

        # otherwise, it all must be OK
        $ga_map{$_} = $action for keys %grades;
    }

    return scalar(keys %ga_map) ? \%ga_map : undef;
}

sub _validate_transport {
    my ($name, $option, $config) = @_;
    my $transport = '';

    if ( $option =~ /^(\w+(?:::\w+)*)\s?/ ) {
        $transport = $1;
        my $full_class = "Test::Reporter::Transport::$transport";
        eval "use $full_class ()";
        if ($@) {
            $CPAN::Frontend->mywarn(
                "\nCPAN::Reporter: error loading $full_class. Please install the missing module or choose a different transport mechanism.\n\n"
            );
        }
    }
    else {
        $CPAN::Frontend->mywarn(
            "\nCPAN::Reporter: Please provide a transport mechanism.\n\n"
        );
        return;
    }

    # we do extra validation for Metabase and offer to create the profile
    if ( $transport eq 'Metabase' ) {
        unless ( $option =~ /\buri\s+\S+/ ) {
            $CPAN::Frontend->mywarn(
                "\nCPAN::Reporter: Please provide a target uri.\n\n"
            );
            return;
        }

        unless ( $option =~ /\bid_file\s+(\S.+?)\s*$/ ) {
            $CPAN::Frontend->mywarn(
                "\nCPAN::Reporter: Please specify an id_file path.\n\n"
            );
            return;
        }

        my $id_file = _normalize_id_file($1);

        # Offer to create if it doesn't exist
        if ( ! -e $id_file )  {
            my $answer = CPAN::Shell::colorable_makemaker_prompt(
                "\nWould you like to run 'metabase-profile' now to create '$id_file'?", "y"
            );
            if ( $answer =~ /^y/i ) {
                return _generate_profile( $id_file, $config );
            }
            else {
                $CPAN::Frontend->mywarn( <<"END_ID_FILE" );
You can create a Metabase profile by typing 'metabase-profile' in your
command prompt and moving the resulting file to the location you specified.
If you did not specify an absolute path, put it in your .cpanreporter
directory.  You will need to do this before continuing.
END_ID_FILE
                return;
            }
        }
        # Warn and fail validation if there but not readable
        elsif (
            not (       -r $id_file
                    or  -r File::Spec->catdir(_get_config_dir(), $id_file)
                )
        ) {
            $CPAN::Frontend->mywarn(
                "CPAN::Reporter: '$id_file' was not readable.\n\n"
            );
            return;
        }
    } # end Metabase

    return 1;
}

sub _validate_seconds {
    my ($name, $option) = @_;
    return unless defined($option) && length($option)
        && ($option =~ /^\d/) && $option >= 0;
    return $option;
}

sub _validate_skipfile {
    my ($name, $option) = @_;
    return unless $option;
    my $skipfile = File::Spec->file_name_is_absolute( $option )
                 ? $option : File::Spec->catfile( _get_config_dir(), $option );
    return -r $skipfile ? $skipfile : undef;
}

1;

# ABSTRACT: Config file options for CPAN::Reporter

__END__

=begin wikidoc

= SYNOPSIS

From the CPAN shell:

 cpan> o conf init test_report

= DESCRIPTION

Default options for CPAN::Reporter are read from a configuration file
{.cpanreporter/config.ini} in the user's home directory.  (On Win32 platforms,
the directory will be located in the user's "Documents" directory.)
The location of the configuration directory or file may be specified
using environment variables instead.

The configuration file is in "ini" format, with the option name and value
separated by an "=" sign

  email_from = "John Doe" <johndoe@nowhere.org>
  edit_report = no

Interactive configuration of email address and common
action prompts may be repeated at any time from the CPAN shell.

 cpan> o conf init test_report

If a configuration file does not exist, it will be created the first
time interactive configuration is performed.

Subsequent interactive configuration will also include any advanced
options that have been added manually to the configuration file.

= INTERACTIVE CONFIGURATION OPTIONS

== Email Address (required)

  email_from = <email address>

CPAN::Reporter requires users to provide an email address that will be used
in the header of the report.

The email address provided should be a valid address format, e.g.:

 email_from = user@domain
 email_from = John Doe <user@domain>
 email_from = "John Q. Public" <user@domain>

== Transport (required)

  transport = <transport class> [transport args]

This sets the transport mechanism passed to the {transport()} method of
[Test::Reporter]. Normally, CPAN::Reporter uses 'Metabase' for transport class
(i.e. [Test::Reporter::Transport::Metabase]) and will provide a default set of
transport arguments.

Metabase transport arguments are two space-separated key/value pairs:

* {uri} -- URI for the Metabase API. Defaults to
{https://metabase.cpantesters.org/api/v1/}
* {id_file} -- path to the user's Metabase profile file.
Defaults to {metabase_id.json}.  (Assumed to be in the {.cpanreporter}
directory).

Prior to sending reports, a user must have a valid profile file at the path
specified.  For Metabase transport, CPAN::Reporter will automatically rewrite a
relative {id_file} path as an absolute path located in the {.cpanreporter}
directory.

If the specified profile file does not exist, CPAN::Reporter will offer
to run {metabase-profile} to create it.

For other transport types, see the documentation that comes with your choice of
Test::Reporter::Transport subclass for the proper way to set the {transport}
configuration option.

== Action Prompts

Several steps in the generation of a test report are optional.  Configuration
options control whether an action should be taken automatically or whether
CPAN::Reporter should prompt the user for the action to take.  The action to
take may be different for each report grade.  For example, users may wish to
customize for which grades they wish to manually review a report before sending
it.

Most users should just accept the default settings until they have some
experience as CPAN Testers.

Valid actions, and their associated meaning, are as follows:

* {yes} -- automatic yes
* {no} -- automatic no
* {ask/no} or just {ask} -- ask each time, but default to no
* {ask/yes} -- ask each time, but default to yes

For "ask" prompts, the default will be used if return is pressed immediately at
the prompt or if the {PERL_MM_USE_DEFAULT} environment variable is set to a
true value.

Action prompt options take one or more space-separated "grade:action" pairs,
which are processed left to right.

 edit_report = fail:ask/yes pass:no

An action by itself is taken as a default to be used for any grade which does
not have a grade-specific action.  A default action may also be set by using
the word "default" in place of a grade.

 edit_report = ask/no
 edit_report = default:ask/no

A grade by itself is taken to have the action "yes" for that grade.

 edit_report = default:no fail

Multiple grades may be specified together by separating them with a slash.

 edit_report = pass:no fail/na/unknown:ask/yes

The action prompt options included in interactive configuration are:

* {edit_report = <grade:action> ...} -- edit the test report before sending?
(default:ask/no pass/na:no)
* {send_report = <grade:action> ...} -- should test reports be sent at all?
(default:ask/yes pass/na:yes)

Note that if {send_report} is set to "no", CPAN::Reporter will still go through
the motions of preparing a report, but will discard it rather than send it.

A better way to disable CPAN::Reporter temporarily is with the CPAN option
{test_report}:

 cpan> o conf test_report 0

== Mail Server (DEPRECATED)

CPAN::Reporter used to send mail directly to perl.org mail servers. The
{smtp_server} option is now deprecated and will be ignored if it exists.

= ADVANCED CONFIGURATION OPTIONS

These additional options are only necessary in special cases, for example if
the default editor cannot be found or if reports shouldn't be sent in
certain situations or for automated testing, and so on.

* {command_timeout} -- if greater than zero and the CPAN config is
{inactivity_timeout} is not set, then any commands executed by CPAN::Reporter
will be halted after this many seconds; useful for unattended smoke testing
to stop after some amount of time; generally, this should be large --
900 seconds or more -- as some distributions' tests take quite a long time to
run.  On MSWin32, [Win32::Job] is a needed and trying to kill a process may
actually deadlock in some situations -- so use at your own risk.
* {editor = <editor>} -- editor to use to edit the test report; if not set,
Test::Reporter will use environment variables {VISUAL}, {EDITOR} or {EDIT}
(in that order) to find an editor
* {retry_submission} -- if greater than zero, CPAN::Reporter will try to
resend the report after a few seconds in case the first attempt fails.
* {send_duplicates = <grade:action> ...} -- should duplicates of previous
reports be sent, regardless of {send_report}? (default:no)
* {send_PL_report = <grade:action> ...} -- if defined, used in place of
{send_report} during the PL phase
* {send_make_report = <grade:action> ...} -- if defined, used in place of
{send_report} during the make phase
* {send_test_report = <grade:action> ...} -- if defined, used in place of
{send_report} during the test phase
* {send_skipfile = <skipfile>} -- filename containing regular expressions (one
per line) to match against the distribution ID (e.g.
'AUTHOR/Dist-Name-0.01.tar.gz'); the report will not be sent if a match is
found; non-absolute filename must be in the .cpanreporter config directory;

If these options are manually added to the configuration file, they will
be included (and preserved) in subsequent interactive configuration.

== Skipfile regular expressions

Skip files are expected to have one regular expression per line and will be
matched against the distribution ID, composed of the author's CPAN ID and the
distribution tarball name.

    DAGOLDEN/CPAN-Reporter-1.00.tar.gz

Lines that begin with a sharp (#) are considered comments and will not be
matched.  All regular expressions will be matched case insensitive and will
not be anchored unless you provide one.

As the format of a distribution ID is "AUTHOR/tarball", anchoring at the
start of the line with a caret (^) will match the author and with a slash (/)
will match the distribution.

    # any distributions by JOHNDOE
    ^JOHNDOE
    # any distributions starting with Win32
    /Win32
    # a particular very specific distribution
    ^JOHNDOE/Foo-Bar-3.14

= CONFIGURATION OPTIONS FOR DEBUGGING

These options are useful for debugging only:

* {debug = <boolean>} -- turns debugging on/off

= ENVIRONMENT

The following environment variables may be set to alter the default locations
for CPAN::Reporter files:

* {PERL_CPAN_REPORTER_DIR} -- if set, this directory is used in place of
the default {.cpanreporter} directory; this will affect not only the location
of the default {config.ini}, but also the location of the
[CPAN::Reporter::History] database and any other files that live in that
directory
* {PERL_CPAN_REPORTER_CONFIG} -- if set, this file is used in place of
the default {config.ini} file; it may be in any directory, regardless of the
choice of configuration directory

= SEE ALSO

* [CPAN::Reporter]
* [CPAN::Reporter::History]
* [CPAN::Reporter::FAQ]

=end wikidoc

=cut

# vim: ts=4 sts=4 sw=4 et:
