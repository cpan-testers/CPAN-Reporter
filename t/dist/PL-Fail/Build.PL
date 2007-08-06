use strict;
use Module::Build;

die "Build.PL should die!\n";

Module::Build->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    create_makefile_pl  => 'traditional',
)->create_build_script;
