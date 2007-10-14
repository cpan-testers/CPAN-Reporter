use strict;
use Module::Build;

Module::Build->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    PL_files            => { 'Die.PL' => 'impossible_file.pm' },
    requires            => { 'Unavailable::Module' => 0 },
)->create_build_script;
