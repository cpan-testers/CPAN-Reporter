package t::MockCPANDist;
use strict;
BEGIN { if ( not $] < 5.006 ) { require warnings; warnings->import } }
use File::Basename;

#--------------------------------------------------------------------------#

my $simulate_bad_author = 0;

sub import {
    my $class = shift;
    $simulate_bad_author = grep { $_ eq 'bad_author' } @_;
}

#--------------------------------------------------------------------------#

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

# cheat on author() and let the mock handle it all unless we want it to fail
sub author { return $simulate_bad_author ? undef : shift } 

sub prereq_pm { return shift->{prereq_pm} }
sub pretty_id { return shift->{pretty_id} }
sub id { return shift->{author_id} }
sub fullname { return shift->{author_fullname} }
sub base_id {
    my $self = shift;
    my $id = $self->pretty_id();
    my $base_id = File::Basename::basename($id);
    $base_id =~ s{\.(?:tar\.(bz2|gz|Z)|t(?:gz|bz)|zip)$}{}i;
    return $base_id;
}


1;
