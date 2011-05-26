use strict; # make CPANTS happy
package CPAN::Reporter::FAQ;
# ABSTRACT: Answers and tips for using CPAN::Reporter

# Not really a .pm file, but holds wikidoc which will be
# turned into .pod by the Build.PL
1;
__END__

=begin wikidoc

= REPORT GRADES

== Why did I receive a report? 

Historically, CPAN Testers was designed to have each tester send a copy of
reports to authors.  This philosophy changed in September 2008 and CPAN Testers
tools were updated to no longer copy authors, but some testers may still be
using an older versions.

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
many Internet Service Providers (ISP's) will block
outbound SMTP (email) connections as part of their efforts to fight spam.
Instead, email must be routed to the ISP's outbound mail servers, which will
relay the email to the intended destination.

Nowadays test reports are sent via Metabase over HTTPS. The most
common reason for failures are systems which upgraded but are still
configured to use the deprecated and unsupported email system
instead of Metabase for transport.

If you are unsure which transport mechanism you're using, look for the
"transport" rule in the {.cpanreporter/config.ini} file, in the
user's home directory.

Other issue might be the absence of the {.cpanreporter/metabase_id.json}
file in the user's home directory. This file should be manually created
prior to sending any reports, via the {metabase-profile} program. Simply
run it and fill the informations accordingly, and it will create
the {metabase_id.json} file for you. Move that file to the
user's {.cpanreporter} directory and you're all set.

Finally, lack of Internet connection or firewall filtering will prevent
the report from reaching the CPAN Testers servers. If you are experiencing
HTTPS issues or messages complaining about SSL modules, try installing
the [LWP::Protocol::https] module and trying again. If all fails, you
may still change the transport uri to use HTTP instead of HTTPS, though
this is ~not~ recommended.


== Why didn't my test report show up on CPAN Testers?

CPAN Testers uses a mailing list to collect test reports.  If the email
address you set in {email_from} is subscribed to the list, your emails
will be automatically processed.  Otherwise, test reports will be held 
until manually reviewed and approved.  

Subscribing an account to the cpan-testers list is as easy as sending a blank
email to cpan-testers-subscribe@perl.org and replying to the confirmation
email.

There is a delay between the time emails appear on the mailing list and the
time they appear on the CPAN Testers website. There is a further delay before
summary statistics appear on search.cpan.org.

If your email address is subscribed to the list but your test reports are still
not showing up, your outbound email may have been silently blocked by your
ISP.  See the question above about errors sending reports.

= CPAN TESTERS

== Where can I find out more about CPAN Testers?

A good place to start is the CPAN Testers Wiki: 
[http://wiki.cpantesters.org/]

== Where can I find statistics about reports sent to CPAN Testers?

CPAN Testers statistics are compiled at [http://stats.cpantesters.org/]

== How do I make sure I get credit for my test reports?

To get credit in the statistics, use the same email address wherever 
you run tests.

For example, if you are a CPAN author, use your PAUSEID email address.

 email_from = pauseid@cpan.org

Otherwise, you should use a consistent "Full Name" as part of your 
email address in the {email_from} option.

 email_from = "John Doe" <john.doe@example.com> 

= SEE ALSO

* [CPAN::Testers]
* [CPAN::Reporter]
* [Test::Reporter]

=end wikidoc

