use strict;
package CPAN::Reporter::PrereqCheck;
# VERSION

use ExtUtils::MakeMaker 6.36;
use File::Spec;
use CPAN::Version;

_run() if ! caller();

sub _run {
    my %saw_mod;
    # read module and prereq string from STDIN
    local *DEVNULL;
    open DEVNULL, ">" . File::Spec->devnull; ## no critic
    # ensure actually installed, not ./inc/... or ./t/..., etc.
    local @INC = grep { $_ ne '.' } @INC;
    while ( <> ) {
        m/^(\S+)\s+([^\n]*)/;
        my ($mod, $need) = ($1, $2);
        die "Couldn't read module for '$_'" unless $mod;
        $need = 0 if not defined $need;

        # only evaluate a module once
        next if $saw_mod{$mod}++;

        # get installed version from file with EU::MM
        my($have, $inst_file, $dir, @packpath);
        if ( $mod eq "perl" ) {
            $have = $];
        }
        else {
            @packpath = split( /::/, $mod );
            $packpath[-1] .= ".pm";
            if (@packpath == 1 && $packpath[0] eq "readline.pm") {
                unshift @packpath, "Term", "ReadLine"; # historical reasons
            }
            INCDIR:
            foreach my $dir (@INC) {
                my $pmfile = File::Spec->catfile($dir,@packpath);
                if (-f $pmfile){
                    $inst_file = $pmfile;
                    last INCDIR;
                }
            }

            # get version from file or else report missing
            if ( defined $inst_file ) {
                $have = MM->parse_version($inst_file);
                $have = "0" if ! defined $have || $have eq 'undef';
                # report broken if it can't be loaded
                # "select" to try to suppress spurious newlines
                select DEVNULL; ## no critic
                if ( ! _try_load( $mod, $have ) ) {
                    select STDOUT; ## no critic
                    print "$mod 0 broken\n";
                    next;
                }
                select STDOUT; ## no critic
            }
            else {
                print "$mod 0 n/a\n";
                next;
            }
        }

        # complex requirements are comma separated
        my ( @requirements ) = split /\s*,\s*/, $need;

        my $passes = 0;
        RQ:
        for my $rq (@requirements) {
            if ($rq =~ s|>=\s*||) {
                # no-op -- just trimmed string
            } elsif ($rq =~ s|>\s*||) {
                if (CPAN::Version->vgt($have,$rq)){
                    $passes++;
                }
                next RQ;
            } elsif ($rq =~ s|!=\s*||) {
                if (CPAN::Version->vcmp($have,$rq)) {
                    $passes++; # didn't match
                }
                next RQ;
            } elsif ($rq =~ s|<=\s*||) {
                if (! CPAN::Version->vgt($have,$rq)){
                    $passes++;
                }
                next RQ;
            } elsif ($rq =~ s|<\s*||) {
                if (CPAN::Version->vlt($have,$rq)){
                    $passes++;
                }
                next RQ;
            }
            # if made it here, then it's a normal >= comparison
            if (! CPAN::Version->vlt($have, $rq)){
                $passes++;
            }
        }
        my $ok = $passes == @requirements ? 1 : 0;
        print "$mod $ok $have\n"
    }
    return;
}

sub _try_load {
  my ($module, $have) = @_;

  my @do_not_load = (
    # should not be loaded directly
    qw/Term::ReadLine::Perl Term::ReadLine::Gnu MooseX::HasDefaults Readonly::XS
       POE::Loop::Event SOAP::Constants
       Moose::Meta::TypeConstraint::Parameterizable Moose::Meta::TypeConstraint::Parameterized/,
    'Devel::Trepan', #"require Enbugger; require Devel::Trepan;" starts debugging session

    #removed modules
    qw/Pegex::Mo YAML::LibYAML/,

    #have additional prereqs
    qw/Log::Dispatch::Email::MailSender RDF::NS::Trine Plack::Handler::FCGI Web::Scraper::LibXML/,

    #modify @INC. 'lib' appearing in @INC will prevent correct
    #checking of modules with XS part, for ex. List::Util
    qw/ExtUtils::ParseXS ExtUtils::ParseXS::Utilities/,
    
    #require special conditions to run
    qw/mylib/,

    #do not return true value
    qw/perlsecret/,
  );

  my %loading_conflicts = (
    'signatures' => ['Catalyst'],
    'Dancer::Plugin::FlashMessage' => ['Dancer::Plugin::FlashNote'],
    'Dancer::Plugin::Mongoose' => ['Dancer::Plugin::DBIC'],
    'Dancer::Plugin::DBIC' => ['Dancer::Plugin::Mongoose'],
  ); #modules that conflict with each other
  
  my %load_before = (
    'Tk::Font' => 'Tk',
    'Tk::Widget' => 'Tk',
    'Tk::Label' => 'Tk',
    'Class::MOP::Class' => 'Class::MOP',
    'Moose::Meta::TypeConstraint::Role' => 'Moose',
    'Moose::Meta::TypeConstraint::Union' => 'Moose',
    'Moose::Meta::Attribute::Native' => 'Class::MOP',
  );

  # M::I < 0.95 dies in require, so we can't check if it loads
  # Instead we just pretend that it works
  if ( $module eq 'Module::Install' && $have < 0.95 ) {
    return 1;
  }
  # circular dependency with Catalyst::Runtime, so this module
  # does not depends on it, but still does not work without it.
  elsif ( $module eq 'Catalyst::DispatchType::Regex' && $have <= 5.90032 ) {
    return 1;
  }
  elsif (  grep { $_ eq $module } @do_not_load ) {
    return 1;
  }
  # loading Acme modules like Acme::Bleach can do bad things,
  # so never try to load them; just pretend that they work
  elsif( $module =~ /^Acme::/ ) {
    return 1;
  }

  if ( exists $loading_conflicts{$module} ) {
      foreach my $mod1 ( @{ $loading_conflicts{$module} } ) {
         my $file = "$mod1.pm";
         $file =~ s{::}{/}g;
         if (exists $INC{$file}) {
             return 1;
         }
      }
  }

  if (exists $load_before{$module}) {
      eval "require $load_before{$module};1;";
  }

  my $file = "$module.pm";
  $file =~ s{::}{/}g;

  return eval {require $file; 1}; ## no critic
}

1;

# ABSTRACT: Modulino for prerequisite tests

__END__

=begin wikidoc

= SYNOPSIS

 require CPAN::Reporter::PrereqCheck;
 my $prereq_check = $INC{'CPAN/Reporter/PrereqCheck.pm'};
 my $result = qx/$perl $prereq_check < $prereq_file/;

= DESCRIPTION

This modulino determines whether a list of prerequisite modules are
available and, if so, their version number.  It is designed to be run
as a script in order to provide this information from the perspective of
a subprocess, just like CPAN::Reporter's invocation of {perl Makefile.PL}
and so on.

It reads a module name and prerequisite string pair from each line of input
and prints out the module name, 0 or 1 depending on whether the prerequisite
is satisfied, and the installed module version.  If the module is not
available, it will print "n/a" for the version.  If the module is available
but can't be loaded, it will print "broken" for the version.  Modules
without a version will be treated as being of version "0".

No user serviceable parts are inside.  This modulino is packaged for
internal use by CPAN::Reporter.

= BUGS

Please report any bugs or feature using the CPAN Request Tracker.
Bugs can be submitted through the web interface at
[http://rt.cpan.org/Dist/Display.html?Queue=CPAN-Reporter]

When submitting a bug or request, please include a test-file or a patch to an
existing test-file that illustrates the bug or desired feature.

= SEE ALSO

* [CPAN::Reporter] -- main documentation

=end wikidoc

=cut
