use strict;
use Module::Build;
use Local::Config;

Module::Build->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    dist_abstract       => 'Bogus',
    create_makefile_pl  => 'traditional',
    requires => { }
)->create_build_script;
