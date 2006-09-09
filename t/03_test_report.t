#!perl
use strict;
BEGIN{ if (not $] < 5.006) { require warnings; warnings->import } }

select(STDERR); $|=1;
select(STDOUT); $|=1;


use Test::More 'skip_all' => "test report generation tests not yet completed";;
#use t::MockCPANDist;
#use IO::Capture::Stdout;
#use IO::Capture::Stderr;
#use File::pushd qw/pushd/;
#use File::Path qw/mkpath/;
#use File::Spec;
#use File::Temp qw/tempdir/;
#
#
##--------------------------------------------------------------------------#
## Fixtures
##--------------------------------------------------------------------------#
#
#my $temp_home = tempdir();
#my $home_dir = File::Spec->rel2abs( $temp_home );
#my $config_dir = File::Spec->catdir( $home_dir, ".cpanreporter" );
#my $config_file = File::Spec->catfile( $config_dir, "config.ini" );
#my $bogus_email = 'johndoe@nowhere.com';
#my $bogus_smtp = 'mail.mail.com';
#my %mock_dist = (
#    prereq_pm       => {
#        'File::Spec' => 0,
#    },
#    author_id       => "JOHNQP",
#    author_fullname => "John Q. Public",
#);
#
##--------------------------------------------------------------------------#
## Mocking -- override support/system functions
##--------------------------------------------------------------------------#
#    
#my $stdout = IO::Capture::Stdout->new;
#my $stderr = IO::Capture::Stderr->new;
#
#BEGIN {
#    $INC{"File/HomeDir.pm"} = 1; # fake load
#    $INC{"Test/Reporter.pm"} = 1; # fake load
#}
#
#package File::HomeDir;
#sub my_documents { return $home_dir };
#
#package Test::Reporter;
#sub new { print shift, "\n"; return bless {}, 'Test::Reporter::Mocked' }
#
#package Test::Reporter::Mocked;
#sub AUTOLOAD { return 1 }
#
#package main;
#
##--------------------------------------------------------------------------#
## test config file prep
##--------------------------------------------------------------------------#
#
#require_ok('CPAN::Reporter');
#is( File::HomeDir::my_documents(), $home_dir,
#    "home directory mocked"
#); 
#mkpath $config_dir;
#ok( -d $config_dir,
#    "config directory created"
#);
#
#my $tiny = Config::Tiny->new();
#$tiny->{_}{email_from} = $bogus_email;
#$tiny->{_}{smtp_server} = $bogus_smtp;
#$tiny->{_}{debug} = 1;
#ok( $tiny->write( $config_file ),
#    "created temp config file with a new email address and smtp server"
#);
#
##--------------------------------------------------------------------------#
## Scenarios to test
##   * make/dmake test -- pass, fail, unknown, na
##   * Build test -- pass, fail, unknown, na
##   * dmake and Build with test.pl -- aborts currently
##   * dmake and Build with bad prereqs
##--------------------------------------------------------------------------#
#
#{
#    local $ENV{PERL_MM_USE_DEFAULT} = 1;
#    my $wd = pushd( File::Spec->catdir( qw/t dist Bogus-Pass/ ) );
#    my $dist = t::MockCPANDist->new( %mock_dist, pretty_id => "Bogus::Pass" );
#    
#    $stdout->start;
#    ok( do "Makefile.PL",
#        "ran Makefile.PL"
#    );
#    my $rc = CPAN::Reporter::test( $dist, "dmake test" );
#    $stdout->stop;
#
#    is( $rc , 1, 
#        "CPAN::Reporter::test() returned true"
#    ); 
#} 
