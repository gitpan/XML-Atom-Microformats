=head1 NAME

XML::Atom::Microformats - parse microformats in Atom content

=head1 SYNOPSIS

 use XML::Atom::Microformats;
 
 my $feed = HTML::Microformats
             ->new_feed($xml, $base_uri)
             ->assume_profile(qw(hCard hCalendar));
 print $feed->json(pretty => 1);
 
 use RDF::TrineShortcuts qw(rdf_query);
 my $results = rdf_query($sparql, $feed->model);
 
=cut

package XML::Atom::Microformats;

use common::sense;
use 5.008;

use HTML::Microformats 0.100;
use JSON;
use RDF::Query;
use XML::Atom::OWL 0.100;

our $VERSION = '0.001';
our $HAS_RDFA;

BEGIN
{
	eval "use RDF::RDFa::Parser; use RDF::RDFa::Parser::Config;";
	$HAS_RDFA = $@ ? 0 : 1 ;
}

=head1 DESCRIPTION

The XML::Atom::Microformats module brings the functionality of
L<HTML::Microformats> to Atom 1.0 Syndication feeds. It finds
microformats embedded in the E<lt>contentE<gt> elements
(note: not E<lt>summaryE<gt>) of Atom entries.

The general pattern of usage is to create an XML::Atom::Microformats
object (which corresponds to an Atom 1.0 feed) using the
C<new_feed> method; then ask for the data, as a Perl hashref,
a JSON string, or an RDF::Trine model.

=head2 Constructor

=over 4

=item C<< $feed = XML::Atom::Microformats->new_feed($xml, $base_url) >>

Constructs a feed object.

$xml is the Atom source (string) or an XML::LibXML::Document.

$base_url is the feed URL, important for resolving relative URL references.

=back

=cut

sub new_feed
{
	my ($class, $xml, $base_uri) = @_;
	
	my $awol;

	if ($HAS_RDFA)
	{
		my $cfg = RDF::RDFa::Parser::Config->new('atom', '1.0', atom_parser=>1);
		$awol = RDF::RDFa::Parser->new($xml, $base_uri, $cfg, RDF::Trine::Store::Memory->temporary_store)->consume;
	}
	else
	{
		$awol = XML::Atom::OWL->new($xml, $base_uri, undef, RDF::Trine::Store::Memory->temporary_store)->consume;
	}
	
	my $self = bless { 'AWOL' => $awol , 'base' => $base_uri }, $class;
	return $self->_find_contexts->_prepare_contexts;	
}

sub _find_contexts
{
	my ($self) = @_;
	
	my $sparql = <<SPARQL;
PREFIX awol: <http://bblfish.net/work/atom-owl/2006-06-06/#>
PREFIX iana: <http://www.iana.org/assignments/relation/>
SELECT ?entry ?entryid ?entrylink ?contenttype ?contentbody ?contentbase ?contentlang ?profile
WHERE
{
	?entry a awol:Entry ;
		awol:content ?content ;
		awol:id ?entryid .
	?content a awol:Content ;
		awol:type ?contenttype ;
		awol:body ?contentbody .
	OPTIONAL { ?entry iana:self ?entrylink . }
	OPTIONAL { ?content awol:base ?contentbase . }
	OPTIONAL { ?content awol:lang ?contentlang . }
	OPTIONAL
	{
		{ ?feed awol:entry ?entry ; iana:profile ?profile . }
		UNION { ?entry iana:profile ?profile . }
	}
}
SPARQL

	my $query  = RDF::Query->new($sparql);
	my $result = $query->execute($self->{'AWOL'}->graph);
	my $data = {};
	while (my $row = $result->next)
	{
		my $e = $row->{'entry'}->as_ntriples;
		
		$data->{$e}->{'entryid'}     ||= $row->{'entryid'}->literal_value;
		$data->{$e}->{'contentbody'} ||= $row->{'contentbody'}->literal_value;
		$data->{$e}->{'contenttype'} ||= $row->{'contenttype'}->literal_value;
		$data->{$e}->{'contentlang'} ||= $row->{'contentlang'}->literal_value
			if defined $row->{'contentlang'};
		$data->{$e}->{'contentbase'} ||= $row->{'contentbase'}->uri
			if defined $row->{'contentbase'};
		$data->{$e}->{'entrylink'}   ||= $row->{'entrylink'}->uri
			if defined $row->{'entrylink'};
		
		if (defined $row->{'profile'})
		{
			push @{ $data->{$e}->{'profiles'} }, $row->{'profile'}->uri;
		}
	}
	$self->{'contexts'} = [values %$data];
	
	return $self;
}

sub _prepare_contexts
{
	my ($self) = @_;
	
	foreach my $context (@{$self->{'contexts'}})
	{
		next unless $context->{'contenttype'} eq 'text/html'
			|| $context->{'contenttype'} eq 'application/xhtml+xml';
		
		my $dom;
		my $html = sprintf("<html xml:lang=\"%s\" lang=\"%s\" xmlns=\"http://www.w3.org/1999/xhtml\"><head><title></title></head><body><div>%s</div></body></html>",
			$context->{'contentlang'},
			$context->{'contentlang'},
			$context->{'contentbody'});
		
		my $hmf = HTML::Microformats->new_document(
			$html,
			($context->{'contentbase'} || $self->{'base'}),
			type => $context->{'contenttype'});
		
		if ($@ || !defined $hmf)
		{
			warn sprintf("ENTRY <%s>: %s",
				$context->{'entryid'},
				($@ || "Could not process entry."));
			next;
		}
		
		$hmf->{'context'}->{'document_uri'} = $context->{'entrylink'} || $context->{'entryid'};
		$hmf->add_profile( @{$context->{'profiles'}} );
		
		$context->{'HMF'} = $hmf;
	}
	
	return $self;
}

=head2 Profile Management

HTML::Microformats uses HTML profiles (i.e. the profile attribute on the
HTML <head> element) to detect which Microformats are used on a page. Any
microformats which do not have a profile URI declared will not be parsed.

XML::Atom::Microformats uses a similar mechanism. Because Atom does not
have a E<lt>headE<gt> element, Atom E<lt>linkE<gt> is used instead:

  <link rel="profile" href="http://ufs.cc/x/hcalendar" />

These links can be used on a per-entry basis, or for the whole feed.

Because many feeds fail to properly declare which profiles they use, there
are various profile management methods to tell XML::Atom::Microformats to
assume the presence of particular profile URIs, even if they're actually
missing.

=over 4

=item C<< $feed->add_profile(@profiles) >>,
C<< $feed->entry_add_profile($entryid, @profiles) >>

Using C<add_profile> you can add one or more profile URIs, and they are
treated as if they were found on the document.

For example:

 $feed->add_profile('http://microformats.org/profile/rel-tag')

This is useful for adding profile URIs declared outside the document itself
(e.g. in HTTP headers).

C<entry_add_profile> is a variant to allow you to add a profile which applies
only to one specific entry within the feed, if you know that entry's ID.

=cut

sub add_profile
{
	my ($self, @profiles) = @_;
	foreach my $context (@{$self->{'contexts'}})
	{
		next unless $context->{'HMF'};
		$context->{'HMF'}->add_profile(@profiles);
	}
	return $self;
}

sub entry_add_profile
{
	my ($self, $entry, @profiles) = @_;
	foreach my $context (@{$self->{'contexts'}})
	{
		next unless $context->{'HMF'};
		next unless $context->{'entryid'} eq $entry;
		$context->{'HMF'}->add_profile(@profiles);
	}
	return $self;
}

=item C<< $feed->assume_profile(@microformats) >>,
C<< $feed->entry_assume_profile($entryid, @profiles) >>

For example:

 $feed->assume_profile(qw(hCard adr geo))

This method acts similarly to C<add_profile> but allows you to use
names of microformats rather than URIs. Microformat names are case
sensitive, and must match HTML::Microformats::Format::Foo module names.

C<entry_assume_profile> is a variant to allow you to add a profile which applies
only to one specific entry within the feed, if you know that entry's ID.

=cut

sub assume_profile
{
	my ($self, @profiles) = @_;
	foreach my $context (@{$self->{'contexts'}})
	{
		next unless $context->{'HMF'};
		$context->{'HMF'}->assume_profile(@profiles);
	}
	return $self;
}

sub entry_assume_profile
{
	my ($self, $entry, @profiles) = @_;
	foreach my $context (@{$self->{'contexts'}})
	{
		next unless $context->{'HMF'};
		next unless $context->{'entryid'} eq $entry;
		$context->{'HMF'}->assume_profile(@profiles);
	}
	return $self;
}

=item C<< $feed->assume_all_profiles >>,
C<< $feed->entry_assume_all_profiles($entryid) >>

This method is equivalent to calling C<assume_profile> for
all known microformats.

=back

=cut

sub assume_all_profiles
{
	my ($self) = @_;
	foreach my $context (@{$self->{'contexts'}})
	{
		next unless $context->{'HMF'};
		$context->{'HMF'}->assume_all_profiles;
	}
	return $self;
}

sub entry_assume_all_profiles
{
	my ($self, $entry) = @_;
	foreach my $context (@{$self->{'contexts'}})
	{
		next unless $context->{'HMF'};
		next unless $context->{'entryid'} eq $entry;
		$context->{'HMF'}->assume_all_profiles;
	}
	return $self;
}

=head2 Parsing Microformats

Generally speaking, you can skip this. The C<data>, C<json> and
C<model> methods will automatically do this for you.

=over 4

=item C<< $feed->parse_microformats >>

Scans through the feed, finding microformat objects.

On subsequent calls, does nothing (as everything is already parsed).

=cut

sub parse_microformats
{
	my $self = shift;
	return $self if $self->{'parsed'};
	
	foreach my $context (@{$self->{'contexts'}})
	{
		next unless $context->{'HMF'};
		$context->{'objects'} = $context->{'HMF'}->objects;
	}
	
	$self->{'parsed'} = 1;
	return $self;
}

=item C<< $feed->clear_microformats >>

Forgets information gleaned by C<parse_microformats> and thus allows
C<parse_microformats> to be run again. This is useful if you've modified
added some profiles between runs of C<parse_microformats>.

=back

=cut

sub clear_microformats
{
	my $self = shift;
	
	foreach my $context (@{$self->{'contexts'}})
	{
		$context->{'objects'} = undef;
		next unless $context->{'HMF'};
		$context->{'HMF'}->clear_microformats;
	}
	
	$self->{'parsed'} = 0;
	return $self;
}

=head2 Retrieving Data

These methods allow you to retrieve the feed's data, and do things
with it.

=over 4

=item C<< $feed->objects($format) >>,
C<< $feed->entry_objects($entryid, $format) >>

$format is, for example, 'hCard', 'adr' or 'RelTag'.

Returns a list of objects of that type. (If called in scalar context,
returns an arrayref.)

Each object is, for example, an HTML::Microformat::hCard object, or an
HTML::Microformat::RelTag object, etc. See the relevent documentation
for details.

C<entry_objects> is a variant to allow you to fetch data for
one specific entry within the feed, if you know that entry's ID.

=cut

sub objects
{
	my ($self, $format, $entry) = @_;
	$self->parse_microformats;
	
	my @rv;
	
	foreach my $context (@{$self->{'contexts'}})
	{
		next unless $context->{'HMF'};
		
		if ($entry eq $context->{'entryid'} || !defined $entry)
		{
			my @these = $context->{'HMF'}->objects($format);
			push @rv, @these;
		}
	}
	
	return @rv if (wantarray);
	return \@rv;
}

sub entry_objects
{
	my ($self, $entry, $format) = @_;
	return $self->objects($format, $entry);
}

=item C<< $feed->all_objects >>,
C<< $feed->entry_all_objects($entryid) >>

Returns a hashref of data. Each hashref key is the name of a microformat
(e.g. 'hCard', 'RelTag', etc), and the values are arrayrefs of objects.

Each object is, for example, an HTML::Microformat::hCard object, or an
HTML::Microformat::RelTag object, etc. See the relevent documentation
for details.

C<entry_all_objects> is a variant to allow you to fetch data for
one specific entry within the feed, if you know that entry's ID.

=cut

sub all_objects
{
	my ($self, $entry) = @_;
	my $rv = {};
	
	foreach my $format (HTML::Microformats->formats)
	{
		$rv->{$format} = $self->objects($format, $entry);
	}
	
	return $rv;
}

*entry_all_objects = \&all_objects;

sub TO_JSON
{
	return  $_[0]->all_objects;
}

=item C<< $feed->json(%opts) >>,
C<< $feed->entry_json($entryid, %opts) >>

Returns data roughly equivalent to the C<all_objects> method, but as a JSON
string.

%opts is a hash of options, suitable for passing to the L<JSON>
module's to_json function. The 'convert_blessed' and 'utf8' options are
enabled by default, but can be disabled by explicitly setting them to 0, e.g.

  print $feed->json( pretty=>1, canonical=>1, utf8=>0 );

C<entry_json> is a variant to allow you to fetch data for
one specific entry within the feed, if you know that entry's ID.

=cut

sub json
{
	my ($self, %opts) = @_;
	
	$opts{'convert_blessed'} = 1
		unless defined $opts{'convert_blessed'};
	
	$opts{'utf8'} = 1
		unless defined $opts{'utf8'};

	return to_json($self->all_objects, \%opts);
}

sub entry_json
{
	my ($self, $entry, %opts) = @_;
	
	$opts{'convert_blessed'} = 1
		unless defined $opts{'convert_blessed'};
	
	$opts{'utf8'} = 1
		unless defined $opts{'utf8'};

	return to_json($self->entry_all_objects($entry), \%opts);
}

=item C<< $feed->model(%opts) >>,
C<< $feed->entry_model($entryid, %opts) >>

Returns data as an RDF::Trine::Model, suitable for serialising as
RDF or running SPARQL queries. Quads are used (rather than
triples) which allows you to trace statements to the entries from
which they came.

C<entry_model> is a variant to allow you to fetch data for
one specific entry within the feed, if you know that entry's ID.

$opts{'atomowl'} is a boolean indicating whether or not to
include data from XML::Atom::OWL in the returned model.
If enabled, this always includes AtomOWL data for the whole
feed (not just for a specific entry), even if you use the
C<entry_model> method.

If RDF::RDFa::Parser 1.09_04 or above is installed, then
$opts{'atomowl'} will automatically pull in DataRSS data
too.

=cut

sub model
{
	my ($self, %opts)  = @_;
	my $model = RDF::Trine::Model->temporary_model;
	$self->add_to_model($model, %opts);
	return $model;
}

sub entry_model
{
	my ($self, $entry, %opts)  = @_;
	my $model = RDF::Trine::Model->temporary_model;
	$self->entry_add_to_model($model, %opts);
	return $model;
}

=item C<< $feed->add_to_model($model, %opts) >>,
C<< $feed->entry_add_to_model($entry, $model, %opts) >>.

Adds data to an existing RDF::Trine::Model. Otherwise, the same as C<model>.

=back

=cut

sub add_to_model
{
	my ($self, $model, %opts) = @_;
	$self->parse_microformats;
	
	my %entry_opts = %opts;
	$entry_opts{'atomowl'} = 0;
	foreach my $context (@{$self->{'contexts'}})
	{
		next unless $context->{'HMF'};
		$self->entry_add_to_model($context->{'entryid'}, $model, %entry_opts);
	}
	
	if ($opts{'atomowl'})
	{
		my $iter = $self->{'AWOL'}->graph->as_stream;
		while (my $st = $iter->next)
		{
			$model->add_statement($st);
		}
	}
	
	return $self;
}

sub entry_add_to_model
{
	my ($self, $entry, $model, %opts) = @_;
	$self->parse_microformats;
	
	foreach my $context (@{$self->{'contexts'}})
	{
		next unless $context->{'HMF'};
		next unless $entry eq $context->{'entryid'};
		
		my $iter = $context->{'HMF'}->model->as_stream;
		while (my $st = $iter->next)
		{
			use RDF::TrineShortcuts;
			$model->add_statement(
				RDF::Trine::Statement->new(($st->nodes)[0..2]),
				RDF::Trine::Node::Resource->new($entry),
				);
		}
	}
	
	if ($opts{'atomowl'})
	{
		my $iter = $self->{'AWOL'}->graph->as_stream;
		while (my $st = $iter->next)
		{
			$model->add_statement($st);
		}
	}
	
	return $self;
}

1;

=head1 BUGS

Please report any bugs to L<http://rt.cpan.org/>.

=head1 SEE ALSO

L<XML::Atom::OWL>,
L<HTML::Microformats>,
L<RDF::RDFa::Parser>.

L<http://microformats.org/>, L<http://www.perlrdf.org/>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT

Copyright 2010 Toby Inkster

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

