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

test_requires       'Test::More' => '0.61';

requires            'HTML::Microformats' => 0;
requires            'RDF::Trine'         => '0.112';
requires            'XML::Atom::OWL'     => 0;
requires            'XML::LibXML'        => '1.60';

recommends          'RDF::RDFa::Parser'  => '1.09_04';

resources(
	'homepage'   => "http://search.cpan.org/dist/$dist/",
	'repository' => "http://goddamn.co.uk/viewvc/perlmods/$dist/",
	'bugtracker' => "http://rt.cpan.org/Dist/Display.html?Queue=$dist",
	);
	
write_doap_changes;
write_doap_changes_xml;

include 'Test::Signature';
auto_install;
WriteAll(
	'meta' => 1,
	'sign' => 1,
	);
