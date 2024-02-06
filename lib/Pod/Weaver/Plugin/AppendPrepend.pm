package Pod::Weaver::Plugin::AppendPrepend;

use 5.010001;
use Moose;
with 'Pod::Weaver::Role::Finalizer';

# AUTHORITY
# DATE
# DIST
# VERSION

# regex
has exclude_modules => (
    is => 'rw',
    isa => 'Str',
);
has exclude_files => (
    is => 'rw',
    isa => 'Str',
);
has ignore => (
    is => 'rw',
    #isa => 'Bool',
    default => sub { 1 },
);

sub finalize_document {
    my ($self, $document, $input) = @_;

    my $filename = $input->{filename};

    if (defined $self->exclude_files) {
        my $re = $self->exclude_files;
        eval { $re = qr/$re/ };
        $@ and die "Invalid regex in exclude_files: $re";
        if ($filename =~ $re) {
            $self->log_debug(["skipped file '%s' (matched exclude_files)", $filename]);
            return;
        }
    }

    my $package;
    if ($filename =~ m!^lib/(.+)\.pm$!) {
        $package = $1;
        $package =~ s!/!::!g;
        if (defined $self->exclude_modules) {
            my $re = $self->exclude_modules;
            eval { $re = qr/$re/ };
            $@ and die "Invalid regex in exclude_modules: $re";
            if ($package =~ $re) {
                $self->log (["skipped package %s (matched exclude_modules)", $package]);
                return;
            }
        }
    }

    # get list of head1 commands with their position in document
    my %headlines_pos;
    {
        my $i = -1;
        for (@{ $document->children }) {
            $i++;
            next unless $_->can('command') && $_->command eq 'head1';
            my $name = $_->{content};
            next if defined $headlines_pos{$name};
            $headlines_pos{$name} = $i;
        }
    }
    #$self->log_debug(["current headlines in the document: %s", \%headlines_pos]);

    for my $h (keys %headlines_pos) {
        my ($which, $target) = $h =~ /\A(append|prepend):(.+)\z/;
        next unless $target;
        $self->log_debug(["%s to section %s", $which, $target]);
        unless (defined $headlines_pos{$target}) {
            if ($self->ignore) {
                $self->log(["Skipping $which $target: no such section"]);
                next;
            } else {
                $self->log_fatal(["Can't $which $target: no such section"]);
            }
        }
        my $section_elem = $document->children->[$headlines_pos{$target}];
        my $appprep_elem = $document->children->[$headlines_pos{$h}];
        if ($which eq 'prepend') {
            unshift @{ $section_elem->children }, @{ $appprep_elem->children };
        } else {
            push @{ $section_elem->children }, @{ $appprep_elem->children };
        }

    }

    # delete all append:/prepend: sections
    for my $h (sort {$headlines_pos{$b} <=> $headlines_pos{$a}}
             keys %headlines_pos) {
        next unless $h =~ /\A(append|prepend):/;
        splice @{ $document->children }, $headlines_pos{$h}, 1;
    }
}

1;
# ABSTRACT: Merge append:FOO and prepend:FOO sections in POD

=for Pod::Coverage finalize_document

=head1 SYNOPSIS

In your F<weaver.ini>:

 [-AppendPrepend]
 ;exclude_modules = REGEX
 ;exclude_files = REGEX

In your POD:

 =head1 prepend:FILES

 foo

 =head1 append:COPYRIGHT AND LICENSE

 blah blah blah

In the final document, the text 'foo' will be prepended to the FILES section
while 'blah blah blah' will be appended to the COPYRIGHT AND LICENSE section.
The original prepend:* and append:* sections will be removed.


=head1 DESCRIPTION

This plugin searches for sections named C<prepend:TARGET> and C<append:TARGET>
where I<TARGET> is a section name. The text in C<prepend:*> section will be
prepended to the target section, while text in C<append:*> section will be
appended to the target section. Target section must exist.

This plugin is useful if you have a section generated by other modules but want
to add some text to it.


=head1 CONFIGURATION

=head2 exclude_modules

=head2 exclude_files

=head2 ignore

Bool. Default to true. If set to true (the default), then when target headline
does not exist, instead of dying, ignore append/prepend the headline.

=cut
