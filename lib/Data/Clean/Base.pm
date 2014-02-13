package Data::Clean::Base;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use Scalar::Util qw(blessed);

our $VERSION = '0.14'; # VERSION

sub new {
    my ($class, %opts) = @_;
    my $self = bless {opts=>\%opts}, $class;
    $log->tracef("Cleanser options: %s", \%opts);
    $self->_generate_cleanser_code;
    $self;
}

sub command_call_method {
    my ($self, $args) = @_;
    my $mn = $args->[0];
    die "Invalid method name syntax" unless $mn =~ /\A\w+\z/;
    return "{{var}} = {{var}}->$mn";
}

sub command_call_func {
    my ($self, $args) = @_;
    my $fn = $args->[0];
    die "Invalid func name syntax" unless $fn =~ /\A\w+(::\w+)*\z/;
    return "{{var}} = $fn({{var}})";
}

# old name, deprecated, will be removed someday
sub command_detect_circular {
    my ($self, $args) = @_;
    return '{{var}} = "CIRCULAR"';
}

sub command_one_or_zero {
    my ($self, $args) = @_;
    return "{{var}} = {{var}} ? 1:0";
}

sub command_deref_scalar {
    my ($self, $args) = @_;
    return '{{var}} = ${ {{var}} }';
}

sub command_stringify {
    my ($self, $args) = @_;
    return '{{var}} = "{{var}}"';
}

sub command_replace_with_ref {
    my ($self, $args) = @_;
    return '{{var}} = $ref';
}

sub command_replace_with_str {
    require SHARYANTO::String::Util;

    my ($self, $args) = @_;
    return "{{var}} = ".SHARYANTO::String::Util::qqquote($args->[0]);
}

sub command_unbless {
    require Acme::Damn;

    my ($self, $args) = @_;
    return "{{var}} = Acme::Damn::damn({{var}})";
}

sub command_clone {
    require Data::Clone;

    my ($self, $args) = @_;
    my $limit = $args->[0] // 50;
    return "if (++\$ctr_circ <= $limit) { {{var}} = Data::Clone::clone({{var}}); redo } else { {{var}} = 'CIRCULAR' }";
}

# test
sub command_die {
    my ($self, $args) = @_;
    return "die";
}

sub _generate_cleanser_code {
    my $self = shift;
    my $opts = $self->{opts};

    my (@code, @ifs_ary, @ifs_hash, @ifs_main);

    my $n = 0;
    my $add_if = sub {
        my ($cond0, $act0) = @_;
        for ([\@ifs_ary, '$e', 'ary'],
             [\@ifs_hash, '$h->{$k}', 'hash'],
             [\@ifs_main, '$_', 'main']) {
            my $act  = $act0 ; $act  =~ s/\Q{{var}}\E/$_->[1]/g;
            my $cond = $cond0; $cond =~ s/\Q{{var}}\E/$_->[1]/g;
            #unless (@{ $_->[0] }) { push @{ $_->[0] }, '    say "D:'.$_->[2].' val=", '.$_->[1].', ", ref=$ref"; # DEBUG'."\n" }
            push @{ $_->[0] }, "    ".($n ? "els":"")."if ($cond) { $act }\n";
        }
        $n++;
    };
    my $add_if_ref = sub {
        my ($ref, $act0) = @_;
        $add_if->("\$ref eq '$ref'", $act0);
    };

    my $circ = $opts->{-circular};
    if ($circ) {
        my $meth = "command_$circ->[0]";
        die "Can't handle command $circ->[0] for option '-circular'" unless $self->can($meth);
        my @args = @$circ; shift @args;
        my $act = $self->$meth(\@args);
        $add_if->('$ref && $refs{ {{var}} }++', $act);
    }

    for my $on (grep {/\A\w*(::\w+)*\z/} sort keys %$opts) {
        my $o = $opts->{$on};
        next unless $o;
        my $meth = "command_$o->[0]";
        die "Can't handle command $o->[0] for option '$on'" unless $self->can($meth);
        my @args = @$o; shift @args;
        my $act = $self->$meth(\@args);
        $add_if_ref->($on, $act);
    }
    $add_if_ref->("ARRAY", '$process_array->({{var}})');
    $add_if_ref->("HASH" , '$process_hash->({{var}})');

    for my $p ([-obj => 'blessed({{var}})'], [-ref => '$ref']) {
        my $o = $opts->{$p->[0]};
        next unless $o;
        my $meth = "command_$o->[0]";
        die "Can't handle command $o->[0] for option '$p->[0]'" unless $self->can($meth);
        my @args = @$o; shift @args;
        $add_if->($p->[1], $self->$meth(\@args));
    }

    push @code, 'sub {'."\n";
    push @code, 'my $data = shift;'."\n";
    push @code, 'state %refs;'."\n" if $circ;
    push @code, 'state $ctr_circ;'."\n" if $circ;
    push @code, 'state $process_array;'."\n";
    push @code, 'state $process_hash;'."\n";
    push @code, 'if (!$process_array) { $process_array = sub { my $a = shift; for my $e (@$a) { my $ref=ref($e);'."\n".join("", @ifs_ary).'} } }'."\n";
    push @code, 'if (!$process_hash) { $process_hash = sub { my $h = shift; for my $k (keys %$h) { my $ref=ref($h->{$k});'."\n".join("", @ifs_hash).'} } }'."\n";
    push @code, '%refs = (); $ctr_circ=0;'."\n" if $circ;
    push @code, 'for ($data) { my $ref=ref($_);'."\n".join("", @ifs_main).'}'."\n";
    push @code, '$data'."\n";
    push @code, '}'."\n";

    my $code = join("", @code).";";
    if ($ENV{LOG_CLEANSER_CODE} && $log->is_trace) {
        require SHARYANTO::String::Util;
        $log->tracef("Cleanser code:\n%s",
                     $ENV{LINENUM} // 1 ?
                         SHARYANTO::String::Util::linenum($code) : $code);
    }
    eval "\$self->{code} = $code";
    die "Can't generate code: $@" if $@;
}

sub clean_in_place {
    my ($self, $data) = @_;

    $self->{code}->($data);
}

sub clone_and_clean {
    require Data::Clone;

    my ($self, $data) = @_;
    my $clone = Data::Clone::clone($data);
    $self->clean_in_place($clone);
}

1;
# ABSTRACT: Base class for Data::Clean::*

__END__

=pod

=encoding UTF-8

=head1 NAME

Data::Clean::Base - Base class for Data::Clean::*

=head1 VERSION

version 0.14

=for Pod::Coverage ^(command_.+)$

=head1 METHODS

=head2 new(%opts) => $obj

Create a new instance.

Options specify what to do with problematic data. Option keys are either
reference types or class names, or C<-obj> (to refer to objects, a.k.a. blessed
references), C<-circular> (to refer to circular references), C<-ref> (to refer
to references, used to process references not handled by other options). Option
values are arrayrefs, the first element of the array is command name, to specify
what to do with the reference/class. The rest are command arguments.

Note that arrayrefs and hashrefs are always walked into, so it's not trapped by
C<-ref>.

Default for C<%opts>: C<< -ref => 'stringify' >>.

Available commands:

=over 4

=item * ['stringify']

This will stringify a reference like C<{}> to something like C<HASH(0x135f998)>.

=item * ['replace_with_ref']

This will replace a reference like C<{}> with C<HASH>.

=item * ['replace_with_str', STR]

This will replace a reference like C<{}> with I<STR>.

=item * ['call_method']

This will call a method and use its return as the replacement. For example:
DateTime->from_epoch(epoch=>1000) when processed with [call_method => 'epoch']
will become 1000.

=item * ['call_func', STR]

This will call a function named STR with value as argument and use its return as
the replacement.

=item * ['one_or_zero', STR]

This will perform C<< $val ? 1:0 >>.

=item * ['deref_scalar']

This will replace a scalar reference like \1 with 1.

=item * ['unbless']

This will perform unblessing using L<Acme::Damn>. Should be done only for
objects (C<-obj>).

=item * ['code', STR]

This will replace with STR treated as Perl code.

=item * ['clone', INT]

This command is useful if you have circular references and want to expand/copy
them. For example:

 my $def_opts = { opt1 => 'default', opt2 => 0 };
 my $users    = { alice => $def_opts, bob => $def_opts, charlie => $def_opts };

C<$users> contains three references to the same data structure. With the default
behaviour of C<< -circular => [replace_with_str => 'CIRCULAR'] >> the cleaned
data structure will be:

 { alice   => { opt1 => 'default', opt2 => 0 },
   bob     => 'CIRCULAR',
   charlie => 'CIRCULAR' }

But with C<< -circular => ['clone'] >> option, the data structure will be
cleaned to become (the C<$def_opts> is cloned):

 { alice   => { opt1 => 'default', opt2 => 0 },
   bob     => { opt1 => 'default', opt2 => 0 },
   charlie => { opt1 => 'default', opt2 => 0 }, }

The command argument specifies the number of references to clone as a limit (the
default is 50), since a cyclical structure can lead to infinite cloning. Above
this limit, the circular references will be replaced with a string
C<"CIRCULAR">. For example:

 my $a = [1]; push @$a, $a;

With C<< -circular => ['clone', 2] >> the data will be cleaned as:

 [1, [1, [1, "CIRCULAR"]]]

With C<< -circular => ['clone', 3] >> the data will be cleaned as:

 [1, [1, [1, [1, "CIRCULAR"]]]]

=back

=head2 $obj->clean_in_place($data) => $cleaned

Clean $data. Modify data in-place.

=head2 $obj->clone_and_clean($data) => $cleaned

Clean $data. Clone $data first.

=head1 ENVIRONMENT

=over

=item * LOG_CLEANSER_CODE => BOOL (default: 0)

Can be enabled if you want to see the generated cleanser code. It is logged at
level C<trace>.

=item * LINENUM => BOOL (default: 1)

When logging cleanser code, whether to give line numbers.

=back

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
