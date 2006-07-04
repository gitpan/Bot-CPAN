# $Revision: 1.3 $
# $Id: Makefile.PL,v 1.3 2006/07/04 08:04:29 afoxson Exp $

use inc::Module::Install;

name('Bot-CPAN');
version_from('lib/Bot/CPAN.pm');
abstract('provides CPAN services via IRC');
author('Adam J. Foxson <afoxson@pobox.com>');
license('gpl');

requires('HTTP::Request' => '1.40');
requires('XML::Parser' => '2.34');
requires('URI' => '1.35');
requires('LWP::UserAgent' => '2.033');
requires('Mail::Internet' => '1.74');
requires('Math::Round' => '0.05');
requires('Net::NNTP' => '2.23');
requires('POE' => '0.3502');
requires('Statistics::Descriptive' => '2.6');
requires('XML::RSS::Parser' => '4');
requires('POE::Component::IRC' => '4.93');
requires('Text::Wrap' => '2005.082401');
requires('Error' => '0.16');
requires('Class::Phrasebook' => '0.88');
requires('Attribute::Handlers' => '0.78');
requires('Storable' => '2.15');
requires('CPAN::DistnameInfo' => '0.06');
requires('Compress::Zlib' => '1.41');
requires('File::Listing' => '1.15');
requires('Sort::Versions' => '1.5');

features(
	'utf8 decoding of cpanratings data' => [
		-default => 1,
		recommends('Encode' => '2.18'),
	],
	'support for the \'cpanbot\' wrapper script' => [
		-default => 0,
		recommends('Config::Auto' => '0.16'),
		recommends('Getopt::Long' => '2.35'),
	],
);

include('ExtUtils::AutoInstall');
check_nmake();
auto_install();

&Meta->write;
&Build->write if lc($0) eq 'build.pl';
&Makefile->write if lc($0) eq 'makefile.pl';
