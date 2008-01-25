use strict;
use Module::Build;

# just spin forever and should be interrupted by command_timeout
while (1) {
    sleep 30;
}

Module::Build->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    create_makefile_pl  => 'traditional',
)->create_build_script;
