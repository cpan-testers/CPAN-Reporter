use strict;
use Module::Build;

my $mb = Module::Build->subclass(
  code => q(
    sub ACTION_test {
      die "Can't execute: ... open3: IO::Pipe: Can't spawn-NOWAIT: No such file or directory at C:/strawberry/perl/lib/TAP/Parser/Iterator/Process.pm line 154\n";
    }
  )
);
  
$mb->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    create_makefile_pl  => 'traditional',
    subclass => 
)->create_build_script;
