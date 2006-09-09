package t::MockCPANDist;
use strict;
BEGIN { if ( not $] < 5.006 ) { require warnings; warnings->import } }

my %spec = (
    prereq_pm => 'HASH',
    pretty_id => q{},
    author_id => q{},
    author_fullname => q{},
);

sub new {
    my ($class) = shift;
    die "Arguments to t::MockCPANDist::new() must be key => value pairs"
        if (@_ % 2);
    my %args = @_;
    for my $key ( keys %spec ) {
        if ( 
            ! exists $args{$key} || 
            ( defined ref $args{$key} && ref $args{$key} ne $spec{$key} ) 
        ) {
            die "Argument '$key' must be a " .
                  (defined $spec{$key} ? "$spec{$key} reference" : "scalar" );
        }
    }
    bless \%args, $class;
}

sub author { return shift } # cheat and let the mock handle it all
sub prereq_pm { return shift->{prereq_pm} }
sub pretty_id { return shift->{pretty_id} }
sub id { return shift->{id} }
sub fullname { return shift->{author_fullname} }

1;
