# $Rev: 73 $
# $Id: Makefile.PL 73 2003-07-21 10:58:11Z afoxson $

use inc::Module::Install;

if (-d ".svn") { # this is necessary only because we're using subversion
	require ExtUtils::MakeMaker;
	if ($ExtUtils::MakeMaker::VERSION < 6.06) {
		eval q{
			sub MY::libscan {
				my $path = $_[1];
				return '' if $path =~ /\B\.svn\b/;
				return $path;
			}
		};
	}
}

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
