use strict;
use Module::Build;

my $class = Module::Build->subclass(
    subclass => "FixedMB",
    code => <<'SUBCLASS' );

sub ACTION_build {
    eval "require 5.999999" or die $@;
}
SUBCLASS

$class->new( 
    module_name         => 'Bogus::Module',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    PL_files            => { 'Die.PL' => 'impossible_file.pm' },
    requires            => { 'perl' => 5.999999 },
)->create_build_script;
