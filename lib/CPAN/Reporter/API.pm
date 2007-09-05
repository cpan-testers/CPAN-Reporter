package CPAN::Reporter::API;
# Not really a .pm file, but holds wikidoc which will be
# turned into .pod by the Build.PL
$VERSION = '0.99_08';
use strict; # make CPANTS happy
1;
__END__

=begin wikidoc

= NAME

CPAN::Reporter::API - Programmer's interface to CPAN::Reporter

= VERSION

This documentation refers to version %%VERSION%%

= FUNCTIONS

CPAN::Reporter provides only a few public function for use within CPAN.pm.
They are not imported during {use}.  Ordinary users will never need them.

== {configure()}

 CPAN::Reporter::configure();

Prompts the user to edit configuration settings stored in the CPAN::Reporter
{config.ini} file.  It will create the configuration file if it does not exist.
It is automatically called by CPAN.pm when initializing the 'test_report'
option, e.g.:

 cpan> o conf init test_report

== {record_command()}

 ($output, $exit_value) = CPAN::Reporter::record_command( $cmd, $secs );

Takes a command to be executed via system(), but wraps and tees it to
show the output to the console, capture the output, and capture the
exit code.  Returns an array reference of output lines (merged STDOUT and
STDERR) and the return value from system().  Note that this is {$?}, so the
actual exit value of the command will need to be extracted as described in
[perlvar].

If the command includes a pipe character ('|'), only the part of the 
command prior to the pipe will be wrapped and teed.  The pipe will be
applied to the execution of the wrapper script.  This is essential to 
capture the exit value of the command and should be otherwise transparent.

If a non-zero {$secs} argument is provided, the command will be run with 
a timeout of {$secs} (seconds).  On Win32, [Win32::Process] must be
available or code will fall-back to running without a timeout; also, the
first space-separated element of the command must be absolute, or else
".exe" will be appended and the PATH searched for a matching command.

If the attempt to record fails, a warning will be issued and one or more of 
{$output} or {$exit_value} will be undefined.

== {grade_make()}

 CPAN::Reporter::grade_make( $dist, $command, \@output, $exit);

Given a CPAN::Distribution object, the system command used to build the
distribution (e.g. "make", "perl Build"), an array of lines of output from the
command and the exit value from the command, {grade_make()} determines a grade
for this stage of distribution installation.  If the grade is "pass",
{grade_make()} does *not* send a CPAN Testers report for this stage and returns
true to signal that the build was successful.  Otherwise, a CPAN Testers report
is sent and {grade_make()} returns false.

== {grade_PL()}

 CPAN::Reporter::grade_PL( $dist, $command, \@output, $exit);

Given a CPAN::Distribution object, the system command used to run Makefile.PL
or Build.PL (e.g. "perl Makefile.PL"), an array of lines of output from the
command and the exit value from the command, {grade_PL()} determines a grade
for this stage of distribution installation.  If the grade is "pass",
{grade_PL()} does *not* send a CPAN Testers report for this stage and returns
true to signal that the Makefile.PL or Build.PL ran successfully.  Otherwise, a
CPAN Testers report is sent and {grade_PL()} returns false.

== {grade_test()}

 CPAN::Reporter::grade_test( $dist, $command, \@output, $exit);

Given a CPAN::Distribution object, the system command used to run tests (e.g.
"make test"), an array of lines of output from testing and the exit value from
the system command, {grade_test()} determines a grade for distribution tests.
A CPAN Testers report is then sent unless specified prerequisites were not
satisfied, in which case the report is discarded.  This function returns true
if the grade is "pass" or "unknown" and returns false, otherwise.

== {test()} -- DEPRECATED

 CPAN::Reporter::test( $cpan_dist, $system_command );

This function is maintained for backwards compatibility.  It effectively 
wraps the functionality of {record_command()} and {grade_test()} into
a single function call. It takes a CPAN::Distribution object and the system
command to run distribution tests.

= SEE ALSO

* [CPAN::Reporter]
* [CPAN::Reporter::Config]
* [CPAN::Reporter::FAQ]

= AUTHOR

David A. Golden (DAGOLDEN)

= COPYRIGHT AND LICENSE

Copyright (c) 2006, 2007 by David A. Golden

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at 
[http://www.apache.org/licenses/LICENSE-2.0]

Files produced as output though the use of this software, including
generated copies of boilerplate templates provided with this software,
shall not be considered Derivative Works, but shall be considered the
original work of the Licensor.

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=end wikidoc

