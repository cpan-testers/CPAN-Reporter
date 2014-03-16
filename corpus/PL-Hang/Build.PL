use strict;
use Module::Build;

# just spin and be interrupted by command_timeout
sleep 30;
die "Fail, fail, fail!";

Module::Build->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    create_makefile_pl  => 'traditional',
)->create_build_script;
