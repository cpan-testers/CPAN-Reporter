use strict;
use Module::Build;

my $class = Module::Build->subclass(
    subclass => "FixMB",
    code => <<'SUBCLASS' );

sub ACTION_build {
    eval "require Unavailable::Module 0" or die $@;
}
SUBCLASS

$class->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    PL_files            => { 'Die.PL' => 'impossible_file.pm' },
    requires            => { 'Unavailable::Module' => 0 },
)->create_build_script;
