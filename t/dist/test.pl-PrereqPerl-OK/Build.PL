use strict;
use Module::Build;

Module::Build->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    create_makefile_pl  => 'traditional',
    requires => {
        perl => 5,
    }
)->create_build_script;
