# $Revision: 1.6 $
# $Id: Makefile.PL,v 1.6 2003/08/28 09:32:30 afoxson Exp $

use inc::Module::Install;

name('Bot-CPAN');
version_from('lib/Bot/CPAN.pm');
abstract('provides CPAN services via IRC');
author('Adam J. Foxson <afoxson@pobox.com>');
license('gpl');

requires('Attribute::Handlers' => '0.78');
requires('Class::Phrasebook' => '0.88');
requires('CPANPLUS' => '0.042');
requires('HTTP::Request' => '1.30');
requires('LWP::UserAgent' => '2.003');
requires('Mail::Internet' => '1.58');
requires('Math::Round' => '0.05');
requires('Net::NNTP' => '2.22');
requires('POE' => '0.26');
requires('POE::Component::IRC' => '2.9');
requires('Statistics::Descriptive' => '2.6');
requires('URI' => '1.24');
requires('XML::Parser' => '2.33');
requires('XML::RSS::Parser' => '0.21');

features(
	'utf8 decoding of cpanratings data' => [
		-default => 1,
		recommends('Encode' => '1.97'),
	],
	'support for the \'cpanbot\' wrapper script' => [
		-default => 0,
		recommends('Config::Auto' => '0.03'),
		recommends('Getopt::Long' => '2.23'),
	],
	'better guessing at distribution descriptions' => [
		-default => 1,
		recommends('Module::CPANTS' => '0.20030725'),
	],
);

include('ExtUtils::AutoInstall');
check_nmake();
auto_install();
install_script('bin/cpanbot');

&Meta->write;
&Build->write if lc($0) eq 'build.pl';
&Makefile->write if lc($0) eq 'makefile.pl';
