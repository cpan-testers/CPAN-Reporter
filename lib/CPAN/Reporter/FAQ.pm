use strict; # make CPANTS happy
package CPAN::Reporter::FAQ;
# VERSION

1;

# ABSTRACT: Answers and tips for using CPAN::Reporter

__END__

=begin wikidoc

= REPORT GRADES

== Why did I receive a report? 

Historically, CPAN Testers was designed to have each tester send a copy of
reports to authors.  This philosophy changed in September 2008 and CPAN Testers
tools were updated to no longer copy authors, but some testers may still be
using an older version.

== Why was a report sent if a prerequisite is missing?

As of CPAN::Reporter 0.46, FAIL and UNKNOWN reports with unsatisfied 
prerequisites are discarded.  Earlier versions may have sent these reports 
out by mistake as either an NA or UNKNOWN report.

PASS reports are not discarded because it may be useful to know when tests
passed despite a missing prerequisite.  NA reports are sent because information
about the lack of support for a platform is relevant regardless of
prerequisites.

= SENDING REPORTS

== Why did I get an error sending a test report?

Historically, test reports were sent via ordinary email.
The most common reason for errors sending a report back then was that
many Internet Service Providers (ISP's) would block
outbound SMTP (email) connections as part of their efforts to fight spam.

Since 2010, test reports are sent to the CPAN Testers Metabase over HTTPS. The
most common reason for failures are systems which upgraded CPAN::Reporter but
are still configured to use the deprecated and unsupported email system instead
of Metabase for transport.

If you are unsure which transport mechanism you're using, look for the
{transport} rule in the {.cpanreporter/config.ini} file, in the
user's home directory.  See [CPAN::Reporter::Config] for details on how
to set the {transport} option for Metabase.

Other errors could be caused by the absence of the
{.cpanreporter/metabase_id.json} file in the user's home directory. This file
should be manually created prior to sending any reports, via the
{metabase-profile} program. Simply run it and fill in the information
accordingly, and it will create the {metabase_id.json} file for you. Move that
file to your {.cpanreporter} directory and you're all set.

If you experience intermittent network issues, you can set the
'retry_submission' option to make a second attempt at sending the report
a few seconds later, in case the first one fails. This could be useful for
extremely slow connections.

Finally, lack of Internet connection or firewall filtering will prevent
the report from reaching the CPAN Testers servers. If you are experiencing
HTTPS issues or messages complaining about SSL modules, try installing
the [LWP::Protocol::https] module and trying again. If all fails, you
may still change the transport uri to use HTTP instead of HTTPS, though
this is ~not~ recommended.

== Why didn't my test report show up on CPAN Testers?

There is a delay between the time reports are sent to the Metabase and when
they they appear on the CPAN Testers website. There is a further delay before
summary statistics appear on search.cpan.org.  If your reports do not appear
after 24 hours, please contact the cpan-testers-discuss email list
([http://lists.perl.org/list/cpan-testers-discuss.html]) or join the
{#cpantesters-discuss} IRC channel on {irc.perl.org}.

= CPAN TESTERS

== Where can I find out more about CPAN Testers?

A good place to start is the CPAN Testers Wiki: 
[http://wiki.cpantesters.org/]

== Where can I find statistics about reports sent to CPAN Testers?

CPAN Testers statistics are compiled at [http://stats.cpantesters.org/]

== How do I make sure I get credit for my test reports?

To get credit in the statistics, use the same Metabase profile file
and the same email address wherever you run tests.

= SEE ALSO

* [CPAN::Testers]
* [CPAN::Reporter]
* [Test::Reporter]

=end wikidoc

