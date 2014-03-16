requires "CPAN" => "1.94";
requires "CPAN::Version" => "0";
requires "Capture::Tiny" => "0";
requires "Carp" => "0";
requires "Config::Tiny" => "2.08";
requires "Data::Dumper" => "0";
requires "Devel::Autoflush" => "0.04";
requires "Exporter" => "0";
requires "ExtUtils::MakeMaker" => "6.36";
requires "Fcntl" => "0";
requires "File::Basename" => "0";
requires "File::Find" => "0";
requires "File::Glob" => "0";
requires "File::HomeDir" => "0.58";
requires "File::Path" => "0";
requires "File::Spec" => "3.19";
requires "File::Temp" => "0.16";
requires "IO::File" => "0";
requires "IPC::Cmd" => "0.76";
requires "Parse::CPAN::Meta" => "0";
requires "Probe::Perl" => "0";
requires "Test::Reporter" => "1.54";
requires "constant" => "0";
requires "perl" => "5.006";
requires "strict" => "0";
requires "vars" => "0";

on 'test' => sub {
  requires "Archive::Tar" => "1.54";
  requires "File::Copy::Recursive" => "0.35";
  requires "File::Spec::Functions" => "0";
  requires "File::pushd" => "0.32";
  requires "IO::CaptureOutput" => "1.03";
  requires "List::Util" => "0";
  requires "Test::Harness" => "0";
  requires "Test::More" => "0.62";
  requires "version" => "0";
  requires "warnings" => "0";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "0";
  recommends "CPAN::Meta::Requirements" => "2.120900";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "6.17";
};

on 'develop' => sub {
  requires "Dist::Zilla" => "5.014";
  requires "Dist::Zilla::Plugin::Prereqs" => "0";
  requires "Dist::Zilla::Plugin::RemovePrereqs" => "0";
  requires "Dist::Zilla::PluginBundle::DAGOLDEN" => "0.060";
  requires "File::Spec" => "0";
  requires "File::Temp" => "0";
  requires "IO::Handle" => "0";
  requires "IPC::Open3" => "0";
  requires "Pod::Coverage::TrustPod" => "0";
  requires "Test::CPAN::Meta" => "0";
  requires "Test::More" => "0";
  requires "Test::Pod" => "1.41";
  requires "Test::Pod::Coverage" => "1.08";
};
