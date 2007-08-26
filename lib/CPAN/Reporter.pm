package CPAN::Reporter;
use strict;

$CPAN::Reporter::VERSION = '0.99_04'; 

use Config;
use Config::Tiny ();
use CPAN ();
use Fcntl qw/:flock :seek/;
use File::Basename qw/basename/;
use File::HomeDir ();
use File::Path qw/mkpath rmtree/;
use File::Spec ();
use File::Temp ();
use IO::File ();
use Probe::Perl ();
use Symbol qw/gensym/;
use Tee qw/tee/;
use Test::Reporter ();
use CPAN::Reporter::Config ();

#--------------------------------------------------------------------------#
# Some platforms don't implement flock, so fake it if necessary
#--------------------------------------------------------------------------#

BEGIN {
    eval {
        my $fh = File::Temp->new() or return;
        flock $fh, LOCK_EX;
    };
    if ( $@ ) {
        *CORE::GLOBAL::flock = sub () { 1 };
    }
}

#--------------------------------------------------------------------------#
# public API
#--------------------------------------------------------------------------#

sub configure {
    my $config_dir = _get_config_dir();
    my $config_file = _get_config_file();
    
    mkpath $config_dir if ! -d $config_dir;
    if ( ! -d $config_dir ) {
        $CPAN::Frontend->myprint(
            "\nCouldn't create configuration directory '$config_dir': $!"
        );
        return;
    }

    my $config;
    my $existing_options;
    
    # explain grade:action pairs
    $CPAN::Frontend->myprint( CPAN::Reporter::Config::_grade_action_prompt() );
    
    # read or create
    if ( -f $config_file ) {
        $CPAN::Frontend->myprint(
            "\nFound your CPAN::Reporter config file at:\n$config_file\n"
        );
        $config = _open_config_file();
        # if we can't read it, bail out
        if ( ! $config ) {
            $CPAN::Frontend->mywarn("\n
                CPAN::Reporter configuration will not be changed\n");
            return;
        }
        # clone what's in the config file
        $existing_options = { %{$config->{_}} } if $config;
        $CPAN::Frontend->myprint(
            "\nUpdating your CPAN::Reporter configuration settings:\n"
        );
    }
    else {
        $CPAN::Frontend->myprint(
            "\nNo CPAN::Reporter config file found; creating a new one.\n"
        );
        $config = Config::Tiny->new();
    }
    
    my %spec = CPAN::Reporter::Config::_config_spec();

    for my $k ( CPAN::Reporter::Config::_config_order() ) {
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
                        $option_data->{validate}->($k, $answer)
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
        "\nWriting CPAN::Reporter config file to '$config_file'.\n"
    );
    if ( $config->write( $config_file ) ) {
        return $config->{_};
    }
    else {
        $CPAN::Frontend->mywarn( "\nError writing config file to '$config_file':" . 
             Config::Tiny->errstr(). "\n");
        return;
    }
}

sub grade_make {
    my $result = _init_result( @_ );
    _compute_make_grade($result);
    _print_grade_msg($result->{is_make} ? $Config{make} : 'Build' , $result);
    if( $result->{grade} ne 'pass' ) {
        _dispatch_report( $result );
    }
    return $result->{success};
}

sub grade_PL {
    my $result = _init_result( @_ );
    _compute_PL_grade($result);
    _print_grade_msg($result->{PL_file} , $result);
    if( $result->{grade} ne 'pass' ) {
        _dispatch_report( $result );
    }
    return $result->{success};
}

sub grade_test {
    my $result = _init_result( @_ );
    _compute_test_grade($result);
    if ( $result->{grade} eq 'discard' ) {
        $CPAN::Frontend->mywarn( 
            "\nCPAN::Reporter: Test results were not valid, $result->{grade_msg}\n\n",
            $result->{prereq_pm}, "\n",
            "Test results for $result->{dist_name} will be discarded"
        );
    }
    else {
        _print_grade_msg( "Test", $result );
        _dispatch_report( $result );
    }
    return $result->{success};
}

sub record_command {
    my ($command, $timeout) = @_;

    my ($cmd, $redirect) = _split_redirect($command);

    my $temp_out = File::Temp->new
        or die "Could not create a temporary file for output: $!";

    # Teeing a command loses its exit value so we must wrap the command 
    # and print the exit code so we can read it off of output
    my $cmdwrapper = File::Temp->new
        or die "Could not create a wrapper for $cmd\: $!";

    my $wrap_code;
    if ( $timeout ) {
        $wrap_code = $^O eq 'MSWin32'
                   ? _timeout_wrapper_win32($cmd, $timeout)
                   : _timeout_wrapper($cmd, $timeout);
        warn "$wrap_code\n";
    }
    # if no timeout or timeout wrap code wasn't available
    if ( ! $wrap_code ) {
        $wrap_code = << "HERE";
system('$cmd');
print '($cmd exited with ', \$?, ")\\n";
HERE
    }

    print {$cmdwrapper} $wrap_code;
    $cmdwrapper->close;
    
    # tee the command wrapper
    my $tee_input = Probe::Perl->find_perl_interpreter() .  " $cmdwrapper";
    $tee_input .= " $redirect" if defined $redirect;
    tee($tee_input, { stderr => 1 }, $temp_out);
        
    # read back the output
    my $temp_out2 = IO::File->new($temp_out->filename, "<");
    if ( !$temp_out2 ) {
        $CPAN::Frontend->mywarn( 
            "CPAN::Reporter couldn't read command results for '$cmd'\n" 
        );
        return;
    }
    my @cmd_output = <$temp_out2>;
    if ( ! @cmd_output ) {
        $CPAN::Frontend->mywarn( 
            "CPAN::Reporter didn't capture command results for '$cmd'\n"
        );
        return;
    }

    # extract the exit value
    my $exit_value;
    if ( $cmd_output[-1] =~ m{exited with} ) {
        ($exit_value) = $cmd_output[-1] =~ m{exited with ([-0-9]+)};
        delete $cmd_output[-1];
    }

    return \@cmd_output, $exit_value;
}

sub test {
    my ($dist, $system_command) = @_;
    my ($output, $exit_value) = record_command( $system_command );
    unless ( defined $output && defined $exit_value ) {
        $CPAN::Frontend->mywarn(
            "CPAN::Reporter had errors capturing output. Tests abandoned"
        );
        return;
    }
    grade_test( $dist, $system_command, $output, $exit_value );
}

#--------------------------------------------------------------------------#
# private functions
#--------------------------------------------------------------------------#

#--------------------------------------------------------------------------#
# _compute_PL_grade
#--------------------------------------------------------------------------#

sub _compute_make_grade {
    my $result = shift;
    my ($grade,$msg);
    if ( $result->{exit_value} ) {
        $result->{grade} = "fail";
        $result->{grade_msg} = "Stopped with an error"
    }
    else {
        $result->{grade} = "pass";
        $result->{grade_msg} = "No errors"
    }
    $result->{success} = $result->{grade} eq "pass" ? 1 : 0;
    return;
}

sub _compute_PL_grade {
    my $result = shift;
    my ($grade,$msg);
    if ( $result->{exit_value} ) {
        if (grep /Perl .*? required.*?--this is only .*?/, @{$result->{output}}) {
            $result->{grade} = "na";
            $result->{grade_msg} = "Perl version too low";
        }
        elsif ( grep /OS Unsupported|No support for OS/i, 
                    @{$result->{output}}) {
            $result->{grade} = "na";
            $result->{grade_msg} = "This platform is not supported"
        }
        else {
            $result->{grade} = "fail";
            $result->{grade_msg} = "Stopped with an error"
        }
    }
    else {
        $result->{grade} = "pass";
        $result->{grade_msg} = "No errors"
    }
    $result->{success} = $result->{grade} eq "pass" ? 1 : 0;
    return;
}

#--------------------------------------------------------------------------#
# _compute_test_grade
#--------------------------------------------------------------------------#

sub _compute_test_grade {
    my $result = shift;
    my ($grade,$msg);
    my $output = $result->{output};
    
    # we need to know prerequisites early
    _expand_result( $result );

    # Output strings taken from Test::Harness::
    # _show_results()  -- for versions < 2.57_03 
    # get_results()    -- for versions >= 2.57_03

    # XXX don't shortcut to unknown with _has_tests here because a custom
    # Makefile.PL or Build.PL might define tests in a non-standard way
    
    # check for make or Build
    
    # parse in reverse order for Test::Harness results
    for my $i ( reverse 0 .. $#{$output} ) {
        if ( $output->[$i] =~ m{^All tests successful}ms ) {
            $grade = 'pass';
            $msg = 'All tests successful';
        }
        elsif ( $output->[$i] =~ m{No support for OS|OS unsupported}ims ) {
            $grade = 'na';
            $msg = 'This platform is not supported';
        }
        elsif ( $output->[$i] =~ m{^.?No tests defined}ms ) {
            $grade = 'unknown';
            $msg = 'No tests provided';
        }
        elsif ( $output->[$i] =~ m{^FAILED--no tests were run}ms ) {
            $grade = 'unknown';
            $msg = 'No tests were run';
        }
        elsif ( $output->[$i] =~ m{^FAILED--.*--no output}ms ) {
            $grade = 'fail';
            $msg = 'Tests had no output';
        }
        elsif ( $output->[$i] =~ m{FAILED--Further testing stopped}ms ) {
            $grade = 'fail';
            $msg = 'Bailed out of tests';
        }
        elsif ( $output->[$i] =~ m{^Failed }ms ) {  # must be lowercase
            $grade = 'fail';
            $msg = "Distribution had failing tests";
        }
        else {
            next;
        }
        if ( $grade eq 'unknown' && _has_tests() ) {
            # probably a spurious message from recursive make, so ignore and
            # continue if we can find any standard test files
            $grade = $msg = undef;
            next;
        }
        last if $grade;
    }
    
    # didn't find Test::Harness output we recognized
    if ( ! $grade ) {
        $grade = "unknown";
        $msg = "Couldn't determine a result";
    }

    # With test.pl and 'make test', any t/*.t might pass Test::Harness, but
    # test.pl might still fail, or there might only be test.pl,
    # so use exit code directly
    
    if ( $result->{is_make} && -f "test.pl" && $grade ne 'fail' ) {
        if ( $result->{exit_value} ) {
            $grade = "fail";
            $msg = "'make test' error detected";
        }
        else {
            $grade = "pass";
            $msg = "'make test' no errors";
        }
    }

    # Downgrade failure/unknown grade if we can determine a cause
    # If perl version is too low => 'na'
    # If stated prereqs missing => 'discard'

    if ( $grade eq 'fail' || $grade eq 'unknown' ) {
        # check for unsupported OS
        if ( $output =~ m{No support for OS|OS unsupported}ims ) {
            $grade = 'na';
            $msg = 'This platform is not supported';
        }
        # check for perl version prerequisite or outright failure
        if ( $result->{prereq_pm} =~ m{^\s+!\s+perl\s}ims ) {
            $grade = 'na';
            $msg = 'Perl version too low';
        }
        # check the prereq report for missing or failure flag '!'
        elsif ( $result->{prereq_pm} =~ m{n/a}ims ) {
            $grade = 'discard';
            $msg = 'Prerequisite missing';
        }
        elsif ( $result->{prereq_pm} =~ m{^\s+!}ims ) {
            $grade = 'discard';
            $msg = 'Prerequisite version too low';
        }
    }

    $result->{grade} = $grade;
    $result->{grade_msg} = $msg;
    $result->{success} =  $result->{grade} eq 'pass'
                       || $result->{grade} eq 'unknown';
    return;
}

#--------------------------------------------------------------------------#
# _dispatch_report
#
# Set up Test::Reporter and prompt user for CC, edit, send
#--------------------------------------------------------------------------#

sub _dispatch_report {
    my $result = shift;

    $CPAN::Frontend->myprint(
        "Preparing a CPAN Testers report for $result->{dist_name}\n"
    );

    # Get configuration options
    my $config_obj = _open_config_file();
    my $config;
    $config = _get_config_options( $config_obj ) if $config_obj;
    if ( ! $config->{email_from} ) {
        $CPAN::Frontend->mywarn( << "EMAIL_REQUIRED");
        
CPAN::Reporter requires an email-address in the config file.  
Test report will not be sent. See documentation for configuration details.

EMAIL_REQUIRED
        return;
    }
        
    # Abort if the distribution name is not formatted according to 
    # CPAN Testers requirements: Dist-Name-version.suffix
    # Regex from CPAN-Testers should extract name, separator, version
    # and extension
    my @format_checks = $result->{dist_basename} =~ 
        m{(.+)([\-\_])(v?\d.*)(\.(?:tar\.(?:gz|bz2)|tgz|zip))$}i;
    ;
    if ( ! grep { length } @format_checks ) {
        $CPAN::Frontend->mywarn( << "END_BAD_DISTNAME");
        
The distribution name '$result->{dist_basename}' does not appear to be 
formatted according to CPAN tester guidelines. Perhaps it is not a normal
CPAN distribution.

Test report will not be sent.

END_BAD_DISTNAME

        return;
    }

    # Gather 'expensive' data for the report
    _expand_result( $result);

    # Setup the test report
    my $tr = Test::Reporter->new;
    $tr->grade( $result->{grade} );
    $tr->distribution( $result->{dist_name}  );

    # Skip if duplicate and not sending duplicates
    my $is_duplicate = _is_duplicate( $tr->subject );
    if ( $is_duplicate ) {
        if ( _prompt( $config, "send_duplicates", $tr->grade) =~ /^n/ ) {
            $CPAN::Frontend->mywarn(<< "DUPLICATE_REPORT");

It seems that "@{[$tr->subject]}"
is a duplicate of a previous report you sent to CPAN Testers.

Test report will not be sent.

DUPLICATE_REPORT
            
            return;
        }
    }

    # Continue report setup
    $tr->debug( $config->{debug} ) if defined $config->{debug};
    $tr->from( $config->{email_from} );
    $tr->address( $config->{email_to} ) if $config->{email_to};
    if ( $config->{smtp_server} ) {
        my @mx = split " ", $config->{smtp_server};
        $tr->mx( \@mx );
    }
    
    # Populate the test report
    $tr->comments( _report_text( $result ) );
    $tr->via( 'CPAN::Reporter ' . $CPAN::Reporter::VERSION );
    my @cc;

    # User prompts for action
    if ( _prompt( $config, "cc_author", $tr->grade) =~ /^y/ ) {
        # CC only if we have an author_id
        push @cc, "$result->{author_id}\@cpan.org" if $result->{author_id};
    }
    
    if ( _prompt( $config, "edit_report", $tr->grade ) =~ /^y/ ) {
        my $editor = $config->{editor};
        local $ENV{VISUAL} = $editor if $editor;
        $tr->edit_comments;
    }
    
    if ( _prompt( $config, "send_report", $tr->grade ) =~ /^y/ ) {
        $CPAN::Frontend->myprint( "Sending test report with '" . $tr->grade . 
              "' to " . join(q{, }, $tr->address, @cc) . "\n");
        if ( $tr->send( @cc ) ) {
                _record_history( $tr->subject ) if not $is_duplicate;
        }
        else {
            $CPAN::Frontend->mywarn( $tr->errstr. "\n");
        }
    }
    else {
        $CPAN::Frontend->myprint("Test report not sent\n");
    }

    return;
}

#--------------------------------------------------------------------------#
# _expand_result - add expensive information like prerequisites and
# toolchain that should only be generated if a report will actually
# be sent
#--------------------------------------------------------------------------#

sub _expand_result {
    my $result = shift;
    return if $result->{expanded}++; # only do this once
    $result->{prereq_pm} = _prereq_report( $result->{dist} );
    $result->{env_vars} = _env_report();
    $result->{special_vars} = _special_vars_report();
    $result->{toolchain_versions} = _toolchain_report();
    return;
}

#--------------------------------------------------------------------------#
# _env_report
#--------------------------------------------------------------------------#

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
    TEMP
    TMPDIR
    AUTOMATED_TESTING
    /AUTHOR_TEST/
    INCLUDE
    LIB
    LD_LIBRARY_PATH
    PROCESSOR_IDENTIFIER
    NUMBER_OF_PROCESSORS
);

sub _env_report {
    my @vars_found;
    for my $var ( @env_vars ) {
        if ( $var =~ m{^/(.+)/$} ) {
            push @vars_found, grep { /$1/ } keys %ENV;
        }
        else {
            push @vars_found, $var if exists $ENV{$var};
        }
    }

    my $report = "";
    for my $var ( sort @vars_found ) {
        $report .= "    $var = $ENV{$var}\n";
    }
    return $report;
}

#--------------------------------------------------------------------------#
# _format_distname
#--------------------------------------------------------------------------#

sub _format_distname {
    my $dist = shift;
    my $basename = basename( $dist->pretty_id );
    $basename =~ s/(\.tar\.(?:gz|bz2)|\.tgz|\.zip)$//i;
    return $basename;
}

#--------------------------------------------------------------------------#
# _format_history -- append perl version to subject
#--------------------------------------------------------------------------#

sub _format_history {
    my $line = shift(@_) . " $]"; # append perl version to subject
    $line .= " patch $Config{perl_patchlevel}" if $Config{perl_patchlevel};
    return $line . "\n";
}

#--------------------------------------------------------------------------#
# _get_config_dir
#--------------------------------------------------------------------------#

sub _get_config_dir {
    return ( $^O eq 'MSWin32' )
        ? File::Spec->catdir(File::HomeDir->my_documents, ".cpanreporter")
        : File::Spec->catdir(File::HomeDir->my_home, ".cpanreporter") ;
}

#--------------------------------------------------------------------------#
# _get_config_file
#--------------------------------------------------------------------------#

sub _get_config_file {
    return File::Spec->catdir( _get_config_dir, "config.ini" );
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
                    $CPAN::Frontend->mywarn( "\nInvalid option '$val' in '$option'. Using default instead.\n\n" );
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
# _get_history_file
#--------------------------------------------------------------------------#

sub _get_history_file {
    return File::Spec->catdir( _get_config_dir, "history.db" );
}

#--------------------------------------------------------------------------#
# _has_tests
#--------------------------------------------------------------------------#

sub _has_tests {
    return 1 if -f 'test.pl';
    if ( -d 't' ) {
        local *TESTDIR;
        opendir TESTDIR, 't';
        while ( my $f = readdir TESTDIR ) {
            if ( $f =~ m{\.t$} ) {
                close TESTDIR;
                return 1;
            }
        }
    }
    return 0;
}

#--------------------------------------------------------------------------#
# _init_result -- create and return a hash of values for use in 
# report evaluation and dispatch
#
# takes same argument format as grade_*()
#--------------------------------------------------------------------------#

sub _init_result {
    my ($dist, $system_command, $output, $exit_value) = @_;
    
    my $result = {
        dist => $dist,
        command => $system_command,
        is_make => _is_make( $system_command ),
        output => ref $output eq 'ARRAY' ? $output : [ split /\n/, $output ],
        exit_value => $exit_value,
        # Note: pretty_id is like "DAGOLDEN/CPAN-Reporter-0.40.tar.gz"
        dist_basename => basename($dist->pretty_id),
        dist_name => _format_distname( $dist ),
    };

    # Used in messages to user
    $result->{PL_file} = $result->{is_make} ? "Makefile.PL" : "Build.PL";

    # CPAN might fail to find an author object for some strange dists
    my $author = $dist->author;
    $result->{author} = defined $author ? $author->fullname : "Author";
    $result->{author_id} = defined $author ? $author->id : "" ;

    return $result;
}

#--------------------------------------------------------------------------#
# _is_duplicate
#--------------------------------------------------------------------------#

sub _is_duplicate {
    my $subject = _format_history( shift );
    my $history = _open_history_file('<') or return;
    my $found = 0;
    flock $history, LOCK_SH;
    while ( defined (my $line = <$history>) ) {
        $found++, last if $line eq $subject
    }
    $history->close;
    return $found;
}

#--------------------------------------------------------------------------#
# _is_make
#--------------------------------------------------------------------------#

sub _is_make {
    my $command = shift;
    return $command =~ m{^\S*make|Makefile.PL$}ims ? 1 : 0;
}

#--------------------------------------------------------------------------#
# _max_length
#--------------------------------------------------------------------------#

sub _max_length {
    my $max = length shift;
    for my $term ( @_ ) {
        $max = length $term if length $term > $max;
    }
    return $max;
}

    
#--------------------------------------------------------------------------#
# _open_config_file
#--------------------------------------------------------------------------#

sub _open_config_file {
    my $config_file = _get_config_file();
    my $config = Config::Tiny->read( $config_file )
        or $CPAN::Frontend->mywarn("Couldn't read CPAN::Reporter configuration file " .
                "'$config_file': " . Config::Tiny->errstr() . "\n");
    return $config; 
}

#--------------------------------------------------------------------------#
# _open_history_file
#--------------------------------------------------------------------------#

sub _open_history_file {
    my $mode = shift || '<';
    my $history_filename = _get_history_file();
    return if ( $mode eq '<' && ! -f $history_filename );
    my $history = IO::File->new( $history_filename, $mode )
        or $CPAN::Frontend->mywarn("Couldn't open CPAN::Reporter history file "
        . "'$history_filename': $!\n");
    return $history; 
}

#--------------------------------------------------------------------------#
# _prereq_report
#--------------------------------------------------------------------------#

sub _prereq_report {
    my $dist = shift;
    my (%need, %have, %prereq_met, $report);
    
    my $prereq_pm = $dist->prereq_pm;

    if ( ref $prereq_pm eq 'HASH' ) {
        # is it the new CPAN style with requires/build_requires?
        if (join(q{ }, sort keys %$prereq_pm) eq "build_requires requires") {
            $need{requires} = $prereq_pm->{requires} 
                if  ref $prereq_pm->{requires} eq 'HASH';
            $need{build_requires} = $prereq_pm->{build_requires} 
                if ref $prereq_pm->{build_requires} eq 'HASH';
        }
        else {
            $need{requires} = $prereq_pm;
        }
    }

    # see what prereqs are satisfied in subprocess
    for my $section ( qw/requires build_requires/ ) {
        next unless ref $need{$section} eq 'HASH';
        my @prereq_list = %{ $need{$section} };
        next unless @prereq_list;
        my $prereq_results = _version_finder( @prereq_list );
        for my $mod ( keys %{$prereq_results} ) {
            $have{$section}{$mod} = $prereq_results->{$mod}{have};
            $prereq_met{$section}{$mod} = $prereq_results->{$mod}{met};
        }
    }
    
    # find formatting widths 
    my ($name_width, $need_width, $have_width) = (6, 4, 4);
    for my $section ( qw/requires build_requires/ ) {
        for my $module ( keys %{ $need{$section} } ) {
            my $name_length = length $module;
            my $need_length = length $need{$section}{$module};
            my $have_length = length $have{$section}{$module};
            $name_width = $name_length if $name_length > $name_width;
            $need_width = $need_length if $need_length > $need_width;
            $have_width = $have_length if $have_length > $have_width;
        }
    }

    my $format_str = 
        "  \%1s \%-${name_width}s \%-${need_width}s \%-${have_width}s\n";

    # generate the report
    for my $section ( qw/requires build_requires/ ) {
        if ( keys %{ $need{$section} } ) {
            $report .= "$section:\n\n";
            $report .= sprintf( $format_str, " ", qw/Module Need Have/ );
            $report .= sprintf( $format_str, " ", 
                                 "-" x $name_width, 
                                 "-" x $need_width,
                                 "-" x $have_width );
        }
        for my $module ( sort { lc $a cmp lc $b } keys %{ $need{$section} } ) {
            my $need = $need{$section}{$module};
            my $have = $have{$section}{$module};
            my $bad = $prereq_met{$section}{$module} ? " " : "!";
            $report .= 
                sprintf( $format_str, $bad, $module, $need, $have);
        }
    }
    
    return $report || "    No requirements found\n";
}

#--------------------------------------------------------------------------#
# _print_grade_msg -
#--------------------------------------------------------------------------#

sub _print_grade_msg {
    my ($phase, $result) = @_;
    my ($grade, $msg) = ($result->{grade}, $result->{grade_msg});
    $CPAN::Frontend->myprint( "CPAN::Reporter: $phase result is '$grade'");
    $CPAN::Frontend->myprint(", $msg") if defined $msg && length $msg;
    $CPAN::Frontend->myprint(".\n");
    return;
}

#--------------------------------------------------------------------------#
# _prompt
#
# Note: always returns lowercase
#--------------------------------------------------------------------------#

sub _prompt {
    my ($config, $option, $grade) = @_;
    my %spec = CPAN::Reporter::Config::_config_spec();

    my $dispatch = CPAN::Reporter::Config::_validate_grade_action_pair(
        $option, join(q{ }, "default:no", $config->{$option} || '')
    );
    my $action = $dispatch->{$grade} || $dispatch->{default};

    my $prompt;
    if     ( $action =~ m{^ask/yes}i ) { 
        $prompt = CPAN::Shell::colorable_makemaker_prompt( 
            $spec{$option}{prompt} . " (yes/no)", "yes" 
        );
    }
    elsif  ( $action =~ m{^ask(/no)?}i ) {
        $prompt = CPAN::Shell::colorable_makemaker_prompt( 
            $spec{$option}{prompt} . " (yes/no)", "no" 
        );
    }
    else { 
        $prompt = $action;
    }
    return lc $prompt;
}

#--------------------------------------------------------------------------#
# _record_history
#--------------------------------------------------------------------------#

sub _record_history {
    my $subject = _format_history( shift );
    my $history = _open_history_file('>>') or return;

    flock( $history, LOCK_EX );
    seek( $history, 0, SEEK_END );
    $history->print( $subject );
    flock( $history, LOCK_UN );
    
    $history->close;
    return;
}

#--------------------------------------------------------------------------#
# _report_text
#--------------------------------------------------------------------------#

my %intro_para = (
    'pass' => <<'HERE',
Thank you for uploading your work to CPAN.  Congratulations!
All tests were successful.
HERE

    'fail' => <<'HERE',
Thank you for uploading your work to CPAN.  However, it appears that
there were some problems testing your distribution.
HERE

    'unknown' => <<'HERE',
Thank you for uploading your work to CPAN.  However, attempting to
test your distribution gave an inconclusive result.  This could be because
you did not define tests (or tests could not be found), because
your tests were interrupted before they finished, or because
the results of the tests could not be parsed by CPAN::Reporter.
HERE

    'na' => <<'HERE',
Thank you for uploading your work to CPAN.  While attempting to test this
distribution, the distribution signaled that support is not available either
for this operating system or this version of Perl.  Nevertheless, any 
diagnostic output produced is provided below for reference.
HERE
    
);

sub _report_text {
    my $data = shift;
    my $test_log = join(q{},@{$data->{output}});
    # generate report
    my $output = << "ENDREPORT";
Dear $data->{author},
    
This is a computer-generated test report for $data->{dist_name}, created
automatically by CPAN::Reporter, version $CPAN::Reporter::VERSION, and sent to the CPAN 
Testers mailing list.  If you have received this email directly, it is 
because the person testing your distribution chose to send a copy to your 
CPAN email address; there may be a delay before the official report is
received and processed by CPAN Testers.

$intro_para{ $data->{grade} }
Sections of this report:

    * Tester comments
    * Prerequisites
    * Environment and other context
    * Test output

------------------------------
TESTER COMMENTS
------------------------------

Additional comments from tester: 

[none provided]

------------------------------
PREREQUISITES
------------------------------

Prerequisite modules loaded:

$data->{prereq_pm}
------------------------------
ENVIRONMENT AND OTHER CONTEXT
------------------------------

Environment variables:

$data->{env_vars}
Perl special variables (and OS-specific diagnostics, for MSWin32):

$data->{special_vars}
Perl module toolchain versions installed:

$data->{toolchain_versions}
------------------------------
TEST OUTPUT
------------------------------

Output from '$data->{command}':

$test_log
ENDREPORT

    return $output;
}

#--------------------------------------------------------------------------#
# _special_vars_report
#--------------------------------------------------------------------------#

sub _special_vars_report {
    my $special_vars = << "HERE";
    Perl: \$^X = $^X
    UID:  \$<  = $<
    EUID: \$>  = $>
    GID:  \$(  = $(
    EGID: \$)  = $)
HERE
    if ( $^O eq 'MSWin32' && eval "require Win32" ) { ## no critic
        my @getosversion = Win32::GetOSVersion();
        my $getosversion = join(", ", @getosversion);
        $special_vars .= "    Win32::GetOSName = " . Win32::GetOSName() . "\n";
        $special_vars .= "    Win32::GetOSVersion = $getosversion\n";
        $special_vars .= "    Win32::IsAdminUser = " . Win32::IsAdminUser() . "\n";
    }
    return $special_vars;
}

#--------------------------------------------------------------------------#
# _split_redirect
#--------------------------------------------------------------------------#

sub _split_redirect {
    my $command = shift;
    my ($cmd, $prefix) = ($command =~ m{\A(.+?)(\|.*)\z});
    if (defined $cmd) {
        return ($cmd, $prefix);
    }
    else { # didn't match a redirection
        return $command
    }
}

#--------------------------------------------------------------------------#
# _timeout_wrapper
#--------------------------------------------------------------------------#

sub _timeout_wrapper {
    my ($cmd, $timeout) = @_;
    
    my $wrapper = sprintf << 'HERE', $timeout, $cmd, $cmd;
use strict;
my ($pid, $exitcode);
eval {
    local $SIG{CHLD};
    local $SIG{ALRM} = sub {die 'Timeout'};
    $pid = fork;
    die "Cannot fork: $!\n" unless defined $pid;
    if ($pid) { #parent
        alarm %s;
        waitpid $pid, 0;
        $exitcode = $?;
    } else {    #child
        exec '%s';
    }
};
alarm 0;
die $@ if $@ =~ /Cannot fork/;
if ($@){
    kill 9, $pid if $@ =~ /Timeout/;
    waitpid $pid, 0;
    $exitcode = $?;
}
print '(%s exited with ', $exitcode, ")\n";
HERE
    return $wrapper;
}

#--------------------------------------------------------------------------#
# _timeout_wrapper_win32
#--------------------------------------------------------------------------#

sub _timeout_wrapper_win32 {
    my ($cmd, $timeout) = @_;

    eval "require Win32::Process;";
    if ($@) {
        $CPAN::Frontend->mywarn( << 'HERE' );
CPAN::Reporter needs Win32::Process for inactivity_timeout support.
Continuing without timeout...
HERE
        return;
    }

    my ($program) = split " ", $cmd;
    if (! File::Spec->file_name_is_absolute( $program ) ) {
        my $exe = $program . ".exe";
        my ($path) = grep { -e File::Spec->catfile($_,$exe) }
                     split /$Config{path_sep}/, $ENV{PATH};
        if (! $path) {
            $CPAN::Frontend->mywarn( << "HERE" );
CPAN::Reporter can't locate $exe in the PATH. 
Continuing without timeout...
HERE
            return;
        }
        $program = File::Spec->catfile($path,$exe);
    }

    my $wrapper = sprintf << 'HERE', $program, $cmd, $cmd, $timeout, $cmd;
use strict;
use Win32::Process qw/STILL_ACTIVE NORMAL_PRIORITY_CLASS/;
my ($process,$exitcode);
Win32::Process::Create(
    $process,
    '%s',
    '%s',
    0,
    NORMAL_PRIORITY_CLASS,
    "."
) or die 'Could not spawn %s: ' . "$^E\n";
$process->Wait(%s * 1000);
$process->GetExitCode($exitcode);
if ($exitcode == STILL_ACTIVE) {
    $process->Kill(9);
    $exitcode = 9;
}
print '(%s exited with ', $exitcode, ")\n";
HERE
    return $wrapper;
}

#--------------------------------------------------------------------------#-
# _toolchain_report
#--------------------------------------------------------------------------#

my @toolchain_mods= qw(
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
    YAML
    YAML::Syck
);

sub _toolchain_report {
    my $installed = _version_finder( map { $_ => 0 } @toolchain_mods );

    my $mod_width = _max_length( keys %$installed );
    my $ver_width = _max_length( 
        map { $installed->{$_}{have} } keys %$installed  
    );

    my $format = "    \%-${mod_width}s \%-${ver_width}s\n";

    my $report = "";
    $report .= sprintf( $format, "Module", "Have" );
    $report .= sprintf( $format, "-" x $mod_width, "-" x $ver_width );

    for my $var ( sort keys %$installed ) {
        $report .= sprintf("    \%-${mod_width}s \%-${ver_width}s\n",
                            $var, $installed->{$var}{have} );
    }

    return $report;
}



#--------------------------------------------------------------------------#
# _version_finder
#
# module => version pairs
#
# This is done via an external program to show installed versions exactly
# the way they would be found when test programs are run.  This means that
# any updates to PERL5LIB will be reflected in the results.
#
# File-finding logic taken from CPAN::Module::inst_file().  Logic to 
# handle newer Module::Build prereq syntax is taken from
# CPAN::Distribution::unsat_prereq()
#
#--------------------------------------------------------------------------#

my $version_finder = File::Temp->new
    or die "Could not create temporary support program for versions: $!";
$version_finder->print( << 'END' );
use strict;
use ExtUtils::MakeMaker;
use CPAN::Version;

# read module and prereq string from STDIN
while ( <STDIN> ) {
    m/^(\S+)\s+([^\n]*)/;
    my ($mod, $need) = ($1, $2);
    die "Couldn't read module for '$_'" unless $mod;
    $need = 0 if not defined $need;

    # get installed version from file with EU::MM
    my($have, $inst_file, $dir, @packpath);
    if ( $mod eq "perl" ) { 
        $have = $];
    }
    else {
        @packpath = split /::/, $mod;
        $packpath[-1] .= ".pm";
        if (@packpath == 1 && $packpath[0] eq "readline.pm") {
            unshift @packpath, "Term", "ReadLine"; # historical reasons
        }
        foreach $dir (@INC) {
            my $pmfile = File::Spec->catfile($dir,@packpath);
            if (-f $pmfile){
                $inst_file = $pmfile;
            }
        }
        
        # get version from file or else report missing
        if ( defined $inst_file ) {
            $have = MM->parse_version($inst_file);
            $have = "0" if ! defined $have || $have eq 'undef';
        }
        else {
            print "$mod 0 n/a\n";
            next;
        }
    }

    # complex requirements are comma separated
    my ( @requirements ) = split /\s*,\s*/, $need;

    my $passes = 0;
    RQ: 
    for my $rq (@requirements) {
        if ($rq =~ s|>=\s*||) {
            # no-op -- just trimmed string
        } elsif ($rq =~ s|>\s*||) {
            if (CPAN::Version->vgt($have,$rq)){
                $passes++;
            }
            next RQ;
        } elsif ($rq =~ s|!=\s*||) {
            if (CPAN::Version->vcmp($have,$rq)) { 
                $passes++; # didn't match
            }
            next RQ;
        } elsif ($rq =~ s|<=\s*||) {
            if (! CPAN::Version->vgt($have,$rq)){
                $passes++;
            }
            next RQ;
        } elsif ($rq =~ s|<\s*||) {
            if (CPAN::Version->vlt($have,$rq)){
                $passes++;
            }
            next RQ;
        }
        # if made it here, then it's a normal >= comparison
        if (! CPAN::Version->vlt($have, $rq)){
            $passes++;
        }
    }
    my $ok = $passes == @requirements ? 1 : 0;
    print "$mod $ok $have\n"
}
END
close VERSIONFINDER;

sub _version_finder {
    my %prereqs = @_;

    my $perl = Probe::Perl->find_perl_interpreter();
    my @prereq_results;
    
    my $prereq_input = File::Temp->new
        or die "Could not create temporary input for prereq analysis: $!";
    $prereq_input->print( map { "$_ $prereqs{$_}\n" } keys %prereqs );
    $prereq_input->close;

    my $prereq_result = qx/$perl $version_finder < $prereq_input/;

    my %result;
    for my $line ( split "\n", $prereq_result ) {
        my ($mod, $met, $have) = split " ", $line;
        $result{$mod}{have} = $have;
        $result{$mod}{met} = $met;
    }
    return \%result;
}

1; #this line is important and will help the module return a true value

__END__

#--------------------------------------------------------------------------#
# pod documentation 
#--------------------------------------------------------------------------#

=begin wikidoc

= NAME

CPAN::Reporter - Provides Test::Reporter support for CPAN.pm

= VERSION

This documentation describes version %%VERSION%%.

= SYNOPSIS

From the CPAN shell:

 cpan> install CPAN::Reporter
 cpan> reload cpan
 cpan> o conf init test_report

= DESCRIPTION

CPAN::Reporter is an add-on for the CPAN.pm module that uses [Test::Reporter]
to send the results of module tests to the CPAN Testers project.  Partial
support for CPAN::Reporter is available in CPAN.pm as of version 1.88; full
support is available in CPAN.pm as of version 1.91_53.

The goal of the CPAN Testers project ([http://testers.cpan.org/]) is to
test as many CPAN packages as possible on as many platforms as
possible.  This provides valuable feedback to module authors and
potential users to identify bugs or platform compatibility issues and
improves the overall quality and value of CPAN.

One way individuals can contribute is to send test results for each module that
they test or install.  Installing CPAN::Reporter gives the option of
automatically generating and emailing test reports whenever tests are run via
CPAN.pm.

= GETTING STARTED

== Installation

The first step in using CPAN::Reporter is to install it using whatever
version of CPAN.pm is already installed.  CPAN.pm will be upgraded as
a dependency if necessary.

 cpan> install CPAN::Reporter

If CPAN.pm was upgraded, it needs to be reloaded.

 cpan> reload cpan

== Configuration

If upgrading from a very old version of CPAN.pm, users may be prompted to renew
their configuration settings, including the 'test_report' option to enable
CPAN::Reporter.  

If not prompted automatically, users should manually initialize CPAN::Reporter
support.  After enabling CPAN::Reporter, CPAN.pm will automatically continue
with interactive configuration of CPAN::Reporter options.

 cpan> o conf init test_report

Users will need to enter an email address in one of the following formats:

 johndoe@example.com
 John Doe <johndoe@example.com>
 "John Q. Public" <johnqpublic@example.com>

Because {cpan-testers} uses a mailing list to collect test reports, it is
helpful if the email address provided is subscribed to the list.  Otherwise,
test reports will be held until manually reviewed and approved.  Subscribing an
account to the cpan-testers list is as easy as sending a blank email to
cpan-testers-subscribe@perl.org and replying to the confirmation email.

Users will also be prompted to enter the name of an outbound email server.  It
is recommended to use an email server provided by the user's ISP or company.
Alternatively, leave this blank to attempt to send email directly to perl.org.

Users that are new to CPAN::Reporter should accept the recommended values
for other configuration options.

After completing interactive configuration, be sure to commit (save) the CPAN
configuration changes.

 cpan> o conf commit

See [CPAN::Reporter::Config] for advanced configuration settings.

== Using CPAN::Reporter

Once CPAN::Reporter is enabled and configured, test or install modules with
CPAN.pm as usual.  

For example, to force CPAN to repeat tests for CPAN::Reporter to see how it
works:

 cpan> force test CPAN::Reporter

When distribution tests fail, users will be prompted to edit the report to add
addition information.

= UNDERSTANDING TEST GRADES

CPAN::Reporter will assign one of the following grades to the report:

* {pass} -- all tests were successful  

* {fail} -- one or more tests failed, one or more test files died during
testing or no test output was seen

* {na} -- tests could not be run on this platform or version of perl

* {unknown} -- no test files could be found (either t/*.t or test.pl) or 
a result could not be determined from test output (e.g tests may have hung 
and been interrupted)

In returning results to CPAN.pm, "pass" and "unknown" are considered successful
attempts to "make test" or "Build test" and will not prevent installation.
"fail" and "na" are considered to be failures and CPAN.pm will not install
unless forced.

If prerequisites specified in {Makefile.PL} or {Build.PL} are not available,
no report will be generated and a failure will be signaled to CPAN.pm.

= PRIVACY WARNING

CPAN::Reporter includes information in the test report about environment
variables and special Perl variables that could be affecting test results in
order to help module authors interpret the results of the tests.  This includes
information about paths, terminal, locale, user/group ID, installed toolchain
modules (e.g. ExtUtils::MakeMaker) and so on.  

These have been intentionally limited to items that should not cause harmful
personal information to be revealed -- it does ~not~ include your entire
environment.  Nevertheless, please do not use CPAN::Reporter if you are
concerned about the disclosure of this information as part of your test report.  

Users wishing to review this information may choose to edit the report 
prior to sending it.

= BUGS

Please report any bugs or feature using the CPAN Request Tracker.  
Bugs can be submitted through the web interface at 
[http://rt.cpan.org/Dist/Display.html?Queue=CPAN-Reporter]

When submitting a bug or request, please include a test-file or a patch to an
existing test-file that illustrates the bug or desired feature.

= SEE ALSO

* [CPAN::Reporter::Config] -- advanced configuration settings
* [CPAN::Reporter::FAQ] -- hints and tips
* [http://cpantesters.perl.org] -- project home with all reports
* [http://cpantest.grango.org] -- documentation and wiki

= AUTHOR

David A. Golden (DAGOLDEN)

dagolden@cpan.org

http://www.dagolden.org/

= COPYRIGHT AND LICENSE

Copyright (c) 2006, 2007 by David A. Golden

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

= DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=end wikidoc

=cut
