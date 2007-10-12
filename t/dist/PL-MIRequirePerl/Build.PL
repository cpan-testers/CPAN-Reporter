use strict;
use Module::Build;

die 'ERROR: perl: Version 5.00505 is installed, but we need version >= 5.999999';

Module::Build->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    create_makefile_pl  => 'traditional',
)->create_build_script;
