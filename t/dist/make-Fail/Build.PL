use strict;
use Module::Build;

my $class = Module::Build->subclass(
    class => "Module::Build::WikiDoc",
    code => <<'SUBCLASS', );

    sub ACTION_build {
        die "Build failure";
    }
SUBCLASS

$class->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    PL_files            => { 'Die.PL' => 'impossible_file.pm' },
)->create_build_script;
