use ExtUtils::MakeMaker;

# just spin forever and should be interrupted by command_timeout
while (1) {
    sleep 30;
}

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
