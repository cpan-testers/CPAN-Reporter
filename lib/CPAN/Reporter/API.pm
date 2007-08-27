package CPAN::Reporter::API;
# Not really a .pm file, but holds wikidoc which will be
# turned into .pod by the Build.PL
$VERSION = '0.99_05';
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

dagolden@cpan.org

http://dagolden.com/

= COPYRIGHT AND LICENSE

Copyright (c) 2006, 2007 by David A. Golden

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with
this module.

= DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=end wikidoc

