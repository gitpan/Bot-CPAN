# $Id: Makefile.PL,v 1.2 2003/03/11 11:17:06 afoxson Exp $
# $Revision: 1.2 $

use ExtUtils::MakeMaker;

WriteMakefile(
	'NAME' => 'Bot::CPAN',
	'PM' => {
		'lib/Bot/CPAN.pm' => '$(INST_LIBDIR)/CPAN.pm',
		'lib/Bot/CPAN/Glue.pm' => '$(INST_LIBDIR)/CPAN/Glue.pm',
	},

	'PREREQ_PM' => {
		'Bot::BasicBot' => '0.04',
		'Net::NNTP' => '2.21',
		'Mail::Internet' => '1.58',
		'CPANPLUS' => '0.042',
		'Attribute::Handlers' => '0.77',
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
