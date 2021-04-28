use strict;
use warnings;

use 5.008;

use ExtUtils::MakeMaker 6.17;

my %WriteMakefileArgs = (
  "ABSTRACT" => "Adds CPAN Testers reporting to CPAN.pm",
  "AUTHOR" => "David Golden <dagolden\@cpan.org>",
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.17"
  },
  "DISTNAME" => "CPAN-Reporter",
  "LICENSE" => "apache",
  "MIN_PERL_VERSION" => "5.008",
  "NAME" => "CPAN::Reporter",
  "PREREQ_PM" => {
    "CPAN" => "1.94",
    "CPAN::Version" => 0,
    "Capture::Tiny" => 0,
    "Carp" => 0,
    "Config::Tiny" => "2.08",
    "Data::Dumper" => 0,
    "Devel::Autoflush" => "0.04",
    "Exporter" => 0,
    "ExtUtils::MakeMaker" => "6.36",
    "Fcntl" => 0,
    "File::Basename" => 0,
    "File::Find" => 0,
    "File::Glob" => 0,
    "File::HomeDir" => "0.58",
    "File::Path" => 0,
    "File::Spec" => "3.19",
    "File::Temp" => "0.16",
    "IO::File" => 0,
    "IPC::Cmd" => "0.76",
    "Parse::CPAN::Meta" => 0,
    "Probe::Perl" => 0,
    "Test::Reporter" => "1.54",
    "constant" => 0,
    "strict" => 0,
    "vars" => 0
  },
  "TEST_REQUIRES" => {
    "Archive::Tar" => "1.54",
    "ExtUtils::MakeMaker" => "6.36",
    "File::Spec" => "3.19",
    "File::Spec::Functions" => 0,
    "File::pushd" => "0.32",
    "FindBin" => 0,
    "IO::CaptureOutput" => "1.03",
    "IO::Handle" => 0,
    "Test::Harness" => 0,
    "Test::More" => "0.62",
    "warnings" => 0
  },
  "VERSION" => "1.2019",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "Archive::Tar" => "1.54",
  "CPAN" => "1.94",
  "CPAN::Version" => 0,
  "Capture::Tiny" => 0,
  "Carp" => 0,
  "Config::Tiny" => "2.08",
  "Data::Dumper" => 0,
  "Devel::Autoflush" => "0.04",
  "Exporter" => 0,
  "ExtUtils::MakeMaker" => "6.36",
  "Fcntl" => 0,
  "File::Basename" => 0,
  "File::Find" => 0,
  "File::Glob" => 0,
  "File::HomeDir" => "0.58",
  "File::Path" => 0,
  "File::Spec" => "3.19",
  "File::Spec::Functions" => 0,
  "File::Temp" => "0.16",
  "File::pushd" => "0.32",
  "FindBin" => 0,
  "IO::CaptureOutput" => "1.03",
  "IO::File" => 0,
  "IO::Handle" => 0,
  "IPC::Cmd" => "0.76",
  "Parse::CPAN::Meta" => 0,
  "Probe::Perl" => 0,
  "Test::Harness" => 0,
  "Test::More" => "0.62",
  "Test::Reporter" => "1.54",
  "constant" => 0,
  "strict" => 0,
  "vars" => 0,
  "warnings" => 0
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);
