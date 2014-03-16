use strict;
use Module::Build;
use File::Spec 9999.9;

Module::Build->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    create_makefile_pl  => 'traditional',
    requires => {
        'File::Spec' => 9999.9,
    }
)->create_build_script;
