# $Rev: 82 $
# $Id: Makefile.PL 82 2003-08-20 06:02:45Z afoxson $

use inc::Module::Install;

name('Bot-CPAN');
version_from('lib/Bot/CPAN.pm');
abstract('provides CPAN services via IRC');
author('Adam J. Foxson <afoxson@pobox.com>');
license('perl');

requires('Attribute::Handlers' => '0.78');
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
        -default => 0,
        recommends('Encode' => '1.97'),
    ],
);

include('ExtUtils::AutoInstall');
check_nmake();
auto_install();
#install_script('bin/cpanbot');

&Meta->write;
&Build->write if lc($0) eq 'build.pl';
&Makefile->write if lc($0) eq 'makefile.pl';
