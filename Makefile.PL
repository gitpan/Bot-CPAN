# $Rev: 76 $
# $Id: Makefile.PL 76 2003-08-11 01:44:29Z afoxson $

use inc::Module::Install;

name('Bot-CPAN');
version_from('lib/Bot/CPAN.pm');
abstract('provides CPAN services via IRC');
author('Adam J. Foxson <afoxson@pobox.com>');
license('perl');

requires('Net::NNTP' => '2.22');
requires('Mail::Internet' => '1.58');
requires('CPANPLUS' => '0.042');
requires('Attribute::Handlers' => '0.78');
requires('POE' => '0.26');
requires('POE::Component::IRC' => '2.9');

include('ExtUtils::AutoInstall');
check_nmake();
auto_install();

&Meta->write;
&Build->write if lc($0) eq 'build.pl';
&Makefile->write if lc($0) eq 'makefile.pl';
