# $Rev: 79 $
# $Id: Makefile.PL 79 2003-08-15 14:13:28Z afoxson $

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
requires('XML::Parser' => '2.33');
requires('XML::RSS::Parser' => '0.21');
requires('LWP::UserAgent' => '2.003');
requires('HTTP::Request' => '1.30');
requires('URI' => '1.24');

features(
    'utf8 decoding of cpanratings data' => [
        -default => 0,
        recommends('Encode' => '1.97'),
    ],
);

include('ExtUtils::AutoInstall');
check_nmake();
auto_install();

&Meta->write;
&Build->write if lc($0) eq 'build.pl';
&Makefile->write if lc($0) eq 'makefile.pl';
