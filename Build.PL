use strict;
use Module::Build;
use File::Spec;

my $class = Module::Build->subclass(
    class => "Module::Build::WikiDoc",
    code => <<'SUBCLASS', );

    sub ACTION_wikidoc {
        my $self = shift;
        eval "use Pod::WikiDoc";
        if ( $@ eq '' ) {
            my $parser = Pod::WikiDoc->new({ 
                comment_blocks => 1,
                keywords => { VERSION => $self->dist_version },
            });
            for my $src ( keys %{ $self->find_pm_files() } ) {
                (my $tgt = $src) =~ s{\.pm$}{.pod};
                $parser->filter( {
                    input   => $src,
                    output  => $tgt,
                });
                print "Creating $tgt\n";
                $tgt =~ s{\\}{/}g;
                $self->_add_to_manifest( 'MANIFEST', $tgt );
            }
        }
        else {
            warn "Pod::WikiDoc not available. Skipping wikidoc.\n";
        }
    }

    sub ACTION_test {
        my $self = shift;
        my $missing_pod;
        for my $src ( keys %{ $self->find_pm_files() } ) {
            (my $tgt = $src) =~ s{\.pm$}{.pod};
            $missing_pod = 1 if ! -e $tgt;
        }
        if ( $missing_pod ) {
            $self->depends_on('wikidoc');
            $self->depends_on('build');
        }
        $self->SUPER::ACTION_test;
    }

    sub ACTION_testpod {
        my $self = shift;
        $self->depends_on('wikidoc');
        $self->SUPER::ACTION_testpod;
    }

    sub ACTION_distdir {
        my $self = shift;
        $self->depends_on('wikidoc');
        $self->SUPER::ACTION_distdir;
    }

SUBCLASS

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
        'Test::More'            => 0.45,   # thread-safe
        'Test::Reporter'        => 1.27,
    },
)->create_build_script;
