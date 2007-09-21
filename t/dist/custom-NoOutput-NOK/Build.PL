use strict;
use Module::Build;

my $class = Module::Build->subclass(
    class => 'Module::Build::Custom',
    code => <<'ENDSUB' );

sub ACTION_test {
    my $self = shift;
    require File::Spec;
    $self->run_perl_script(File::Spec->catfile(qw/test Tester.pl/))
        or die "Tests no good!\n";
}

ENDSUB

$class->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    create_makefile_pl  => 'traditional',
)->create_build_script;
