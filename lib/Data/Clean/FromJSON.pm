package Data::Clean::FromJSON;

use 5.010001;
use strict;
use warnings;

use parent qw(Data::Clean::Base);

our $VERSION = '0.16'; # VERSION

sub new {
    my ($class, %opts) = @_;
    $opts{"JSON::XS::Boolean"} //= ['one_or_zero'];
    $opts{"JSON::PP::Boolean"} //= ['one_or_zero'];
    $class->SUPER::new(%opts);
}

sub get_cleanser {
    my $class = shift;
    state $singleton = $class->new;
    $singleton;
}

1;
# ABSTRACT: Clean data from JSON decoder

__END__

=pod

=encoding UTF-8

=head1 NAME

Data::Clean::FromJSON - Clean data from JSON decoder

=head1 VERSION

version 0.16

=head1 SYNOPSIS

 use Data::Clean::FromJSON;
 use JSON;
 my $cleanser = Data::Clean::FromJSON->get_cleanser;
 my $data    = JSON->new->decode('[true]'); # -> [bless(do{\(my $o=1)},"JSON::XS::Boolean")]
 my $cleaned = $cleanser->clean_in_place($data); # -> [1]

=head1 DESCRIPTION

This class can convert L<JSON::PP::Boolean> (or C<JSON::XS::Boolean>) objects to
1/0 values.

=head1 METHODS

=head2 CLASS->get_cleanser => $obj

Return a singleton instance, with default options. Use C<new()> if you want to
customize options.

=head2 CLASS->new(%opts) => $obj

Create a new instance. For list of known options, see L<Data::Clean::Base>.
Data::Clean::FromJSON sets some defaults.

    "JSON::PP::Boolean" => ['one_or_zero']
    "JSON::XS::Boolean" => ['one_or_zero']

=head2 $obj->clean_in_place($data) => $cleaned

Clean $data. Modify data in-place.

=head2 $obj->clone_and_clean($data) => $cleaned

Clean $data. Clone $data first.

=head1 ENVIRONMENT

LOG_CLEANSER_CODE

=head1 FAQ

=head2 Why am I getting 'Modification of a read-only value attempted at lib/Data/Clean/Base.pm line xxx'?

[2013-10-15 ] This is also from Data::Clone::clone() when it encounters
JSON::{PP,XS}::Boolean objects. You can use clean_in_place() instead of
clone_and_clean(), or clone your data using other cloner like L<Storable>.

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/Data-Clean-JSON>.

=head1 SOURCE

Source repository is at L<https://github.com/sharyanto/perl-Data-Clean-JSON>.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=Data-Clean-JSON>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
