use ExtUtils::MakeMaker;

# just spin and be interrupted by command_timeout
sleep 30;
die "Fail, fail, fail!";

WriteMakefile
(
          'PL_FILES' => {},
          'INSTALLDIRS' => 'site',
          'NAME' => 'Bogus::Module',
          'EXE_FILES' => [],
          'VERSION_FROM' => 'lib/Bogus/Module.pm',
          'PREREQ_PM' => {}
        )
;
