use strict;
use lib 'inc';
eval "require Pod::WikiDoc";
my $class = $@ ? "Module::Build" : "Module::Build::WikiDoc";
eval "require $class";
$class->new( 
    module_name         => 'CPAN::Reporter',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    license             => 'perl',
    create_readme       => 1,
    create_makefile_pl  => 'traditional',
    requires        => {
        # module requirements here
        'Config::Tiny'          => 2.08,
        'CPAN'                  => 1.88,
        'ExtUtils::MakeMaker'   => 6.26, # sane ExtUtils::Command::MM
        'File::Basename'        => 0,
        'File::Copy::Recursive' => 0.28,
        'File::HomeDir'         => 0.58, 
        'File::Path'            => 0,
        'File::pushd'           => 0.32,
        'File::Spec'            => 3.19,
        'File::Temp'            => 0.16,
        'IO::CaptureOutput'     => 1.03,  # build_requires
        'Probe::Perl'           => 0,
        'Tee'                   => 0.13,
        'Test::More'            => 0.62, # various features/fixes
        'Test::Reporter'        => 1.30,
    },
    meta_add            => { 
        no_index => { 
            file => [ qw{ 
                lib/CPAN/Reporter/API.pm
                lib/CPAN/Reporter/FAQ.pm
            }],
            directory => [ qw{
                examples
                inc
            }],
        } 
    },
)->create_build_script;
