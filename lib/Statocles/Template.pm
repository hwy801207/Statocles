package Statocles::Template;
# ABSTRACT: A template object to pass around

use Statocles::Base 'Class';
use Mojo::Template;
use Scalar::Util qw( blessed );

=attr content

The main template string. This will be generated by reading the file C<path> by
default.

=cut

has content => (
    is => 'ro',
    isa => Str,
    lazy => 1,
    default => sub {
        my ( $self ) = @_;
        return Path::Tiny->new( $self->path )->slurp;
    },
);

=attr path

The path to the file for this template. Optional.

=cut

has path => (
    is => 'ro',
    isa => Str,
    coerce => sub {
        return "$_[0]"; # Force stringify in case of Path::Tiny objects
    },
);

=attr store

A store to use for includes. Optional.

=cut

has store => (
    is => 'ro',
    isa => Store,
    predicate => 'has_store',
    coerce => Store->coercion,
);

=method BUILDARGS( )

Set the default path to something useful for in-memory templates.

=cut

around BUILDARGS => sub {
    my ( $orig, $self, @args ) = @_;
    my $args = $self->$orig( @args );
    if ( !$args->{path} ) {
        my ( $i, $caller_class ) = ( 0, (caller 0)[0] );
        while ( $caller_class->isa( 'Statocles::Template' )
            || $caller_class->isa( 'Sub::Quote' )
            || $caller_class->isa( 'Method::Generate::Constructor' )
        ) {
            #; say "Class: $caller_class";
            $i++;
            $caller_class = (caller $i)[0];
        }
        #; say "Class: $caller_class";
        $args->{path} = join " line ", (caller($i))[1,2];
    }
    return $args;
};

=method render( %args )

Render this template, passing in %args. Each key in %args will be available as
a scalar in the template.

=cut

sub render {
    my ( $self, %args ) = @_;
    my $t = Mojo::Template->new(
        name => $self->path,
    );
    $t->prepend( $self->_prelude( '_tmpl', keys %args ) );

    my $content;
    {
        # Add the helper subs, like Mojolicious::Plugin::EPRenderer does
        no strict 'refs';
        no warnings 'redefine';
        local *{"@{[$t->namespace]}::include"} = sub {
            $self->_include( \%args, @_ );
        };
        $content = $t->render( $self->content, \%args );
    }

    if ( blessed $content && $content->isa( 'Mojo::Exception' ) ) {
        die "Error in template: " . $content;
    }
    return $content;
}

# Build the Perl string that will unpack the passed-in args
# This is how Mojolicious::Plugin::EPRenderer does it, but I'm probably
# doing something wrong here...
sub _prelude {
    my ( $self, @vars ) = @_;
    return join " ",
        'use strict; use warnings;',
        'my $vars = shift;',
        map( { "my \$$_ = \$vars->{'$_'};" } @vars ),
        ;
}


# Find and include the given file. If it's a template, give it the given vars
sub _include {
    my ( $self, $vars, $name ) = @_;
    if ( !$self->has_store ) {
        die qq{Can not include: No store!};
    }

    my $store = $self->store;
    if ( $store->has_file( "$name.ep" ) ) {
        my $inner_tmpl = __PACKAGE__->new(
            path => "$name.ep",
            content => $store->read_file( "$name.ep" ),
            store => $store,
        );
        return $inner_tmpl->render( %$vars );
    }
    elsif ( $store->has_file( $name ) ) {
        return $store->read_file( $name );
    }

    die qq{Can not find include "$name" in store "$store"};
}

=method coercion

A class method to returns a coercion sub to convert strings into template
objects.

=cut

sub coercion {
    my ( $class ) = @_;
    return sub {
        die "Template is undef" unless defined $_[0];
        return !ref $_[0]
            ? Statocles::Template->new( content => $_[0] )
            : $_[0]
            ;
    };
}

1;
__END__

=head1 DESCRIPTION

This is the template abstraction layer for Statocles.

=head1 TEMPLATE LANGUAGE

The default Statocles template language is Mojolicious's Embedded Perl
template. Inside the template, every key of the %args passed to render() will
be available as a simple scalar:

    # template.tmpl
    % for my $p ( @$pages ) {
    <%= $p->{content} %>
    % }

    my $tmpl = Statocles::Template->new( path => 'template.tmpl' );
    $tmpl->render(
        pages => [
            { content => 'foo' },
            { content => 'bar' },
        ]
    );
