use strict;
use Module::Build;

my $class = Module::Build->subclass(
    class => "Module::Build::Bogus",
    code => <<'SUBCLASS', );

    sub ACTION_test {
        my $self = shift;
        print "\nAll tests successful.\n\n";
        $self->SUPER::ACTION_test;
    }

SUBCLASS

$class->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    create_makefile_pl  => 'traditional',
)->create_build_script;
