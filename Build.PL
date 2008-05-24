use strict;
use lib 'inc';
eval "require Pod::WikiDoc";
my $class = $@ ? "Module::Build" : "Module::Build::WikiDoc";
eval "require $class";
$class->new( 
    module_name         => 'CPAN::Reporter',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    license             => 'apache',
    create_readme       => 1,
    create_makefile_pl  => 'traditional',
    requires        => {
        # module requirements here
        'Config::Tiny'          => 2.08,
        'CPAN'                  => 1.9203,
        'Devel::Autoflush'      => 0,
        'ExtUtils::MakeMaker'   => 6.36, # many bug fixes
        'File::Basename'        => 0,
        'File::Copy::Recursive' => 0.35,
        'File::Find'            => 0,
        'File::HomeDir'         => 0.58, 
        'File::Path'            => 0,
        'File::pushd'           => 0.32,
        'File::Spec'            => 3.19,
        'File::Temp'            => 0.16,  # build_requires
        'IO::CaptureOutput'     => 1.03,  # build_requires
        'Parse::CPAN::Meta'     => 0,
        'Probe::Perl'           => 0,
        'Tee'                   => 0.13,
        'Test::More'            => 0.62, # various features/fixes
        'Test::Reporter'        => 1.40, # transport()
    },
    meta_add            => { 
        no_index => { 
            directory => [ qw{
                examples
                inc
            }],
        } 
    },
)->create_build_script;
