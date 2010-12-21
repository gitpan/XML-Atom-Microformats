use strict;
use warnings;

use inc::Module::Install;

my $dist = 'XML-Atom-Microformats';
my $fn   = "lib/$dist.pm"; $fn =~ s#-#/#g;

name                $dist;
perl_version_from   $fn;
version_from        $fn;
abstract_from       $fn;
readme_from         $fn;
author              'Toby Inkster <tobyink@cpan.org>';
license             'perl';

requires            'HTML::Microformats' => '0.100';
requires            'JSON'               => '2.00';
test_requires       'Module::Signature'  => '0.66';
recommends          'RDF::RDFa::Parser'  => '1.093';
requires            'RDF::Trine'         => '0.118';
requires            'RDF::Query'         => '2.900';
test_requires       'Test::More'         => '0.61';
requires            'XML::Atom::OWL'     => '0.100';
requires            'XML::LibXML'        => '1.60';

resources(
	'homepage'   => "http://search.cpan.org/dist/$dist/",
	'repository' => "http://goddamn.co.uk/viewvc/perlmods/$dist/",
	'bugtracker' => "http://rt.cpan.org/Dist/Display.html?Queue=$dist",
	);

keywords(qw(XML Atom Microformats RDFa RDF SemWeb JSON HTML XHTML Semantic Web));

write_doap_changes;
write_doap_changes_xml;

include 'Test::Signature';
auto_install;
WriteAll(
	'meta' => 1,
	'sign' => 1,
	);
