# $Id: Makefile.PL,v 1.4 2003/03/23 04:43:15 afoxson Exp $
# $Revision: 1.4 $

use ExtUtils::MakeMaker;

print "\n" .
	"    => To use this distribution you'll need to patch POE::Component::IRC <=\n\n" .
	"This patch adds variable priority messaging, and is needed to prevent the bot\n" .
	"from blocking when sending a lot of data back to users. The patch file is for\n" .
	"P::C::I 2.7, and is located in etc/. See POD for details.\n\n";

print "You may safely ignore this message if you've already patched P::C::I 2.7.\n\n";

WriteMakefile(
	'NAME' => 'Bot::CPAN',
	'PM' => {
		'lib/Bot/CPAN.pm' => '$(INST_LIBDIR)/CPAN.pm',
		'lib/Bot/CPAN/Glue.pm' => '$(INST_LIBDIR)/CPAN/Glue.pm',
		'lib/Bot/CPAN/BasicBot.pm' => '$(INST_LIBDIR)/CPAN/BasicBot.pm',
	},

	'PREREQ_PM' => {
		'Net::NNTP' => '2.21',
		'Mail::Internet' => '1.58',
		'CPANPLUS' => '0.042',
		'Attribute::Handlers' => '0.77',
		'POE' => '0.22',
		'POE::Component::IRC' => '2.7',
		'Digest::MD5' => '2.20',
	},
	'VERSION_FROM' => 'lib/Bot/CPAN.pm',
	'MAN3PODS' => {
		'lib/Bot/CPAN.pod' => '$(INST_MAN3DIR)/Bot::CPAN.3',
	},
	'dist' => {
		'COMPRESS' => 'gzip --best',
		'SUFFIX' => '.gz',
	},
	(   
		$] >= 5.005 ?  (   
			ABSTRACT_FROM => 'lib/Bot/CPAN.pod',
			AUTHOR => 'Adam J. Foxson <afoxson@pobox.com>',
		) : ()
	),
);
