# $Revision: 1.7 $
# $Id: CPAN.pm,v 1.7 2003/03/10 06:50:10 afoxson Exp $

# Bot::CPAN - provides CPAN services via IRC
# Copyright (c) 2003 Adam J. Foxson. All rights reserved.
# Copyright (c) 2003 Casey West. All rights reserved.

# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Bot::CPAN;

use strict;
use POE;
use Bot::BasicBot;
use CPANPLUS::Backend;
use Net::NNTP;
use Mail::Internet;
use vars qw(@ISA $VERSION $SERVER $GROUP $HIGHEST_ARTICLE_NUM);
use constant NOT_A_COMMAND => (0);
use constant PUBLIC_COMMAND => (1<<0);
use constant PRIVATE_COMMAND => (1<<1);
use constant FORK => (1<<2);

@ISA = qw(Bot::BasicBot);
$VERSION = '0.01_02';
$SERVER = 'nntp.perl.org'; # may end up storing this elsewhere
$GROUP = 'perl.cpan.testers'; # may end up storing this elsewhere

local $^W;

# may end up storing this elsewhere
my %commands = (
	'author' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'description' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'stage' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'style' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'language' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'package' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'support' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'version' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'path' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'recent' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'fetch' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'readme' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'status' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'url' => PRIVATE_COMMAND|PUBLIC_COMMAND,
	'tests' => PRIVATE_COMMAND|FORK,
	'modules' => PRIVATE_COMMAND|FORK,
	'distributions' => PRIVATE_COMMAND|FORK,
	'details' => PRIVATE_COMMAND|FORK,
	'botsnack' => PUBLIC_COMMAND,
);

sub command {
	my ($self, $body, $who, $type) = @_;
	my $cmds = join '|', keys %commands;
	my @invalid = ('huh?', 'hm?', 'excuse me?', 'pardon me?');
	my $invalid = $invalid[int(rand(scalar @invalid))];

	return $invalid unless $body =~ m/
		^
		(
			$cmds
		)
		(?:
			(?:\s+(?:for|from|of|on|to))?
			\s+
			([^\s\?]+)
		)?
		\s*
		\??
		$
	/imx;

	my ($command, $module_or_author) = ($1, $2);

	unless ($type & $commands{$command}) {
		if ($commands{$command} & PUBLIC_COMMAND) {
			return "'$command' is a public only command";
		}
		elsif ($commands{$command} & PRIVATE_COMMAND) {
			return "'$command' is a private only command";
		}
	}

	$self->set('requests', $self->get('requests') + 1);

	return $self->$command($module_or_author, $who) if
		$commands{$command} & FORK;
	return $self->$command($module_or_author);
}

sub said {
	my ($self, $mess) = @_;
	my $body = $mess->{body};
	my $who = $mess->{who};
	my $type = $mess->{channel} eq 'msg' ? PRIVATE_COMMAND : PUBLIC_COMMAND;

	# say nothing if we are not specifically addressed
	return undef unless $mess->{address}; 

	my $result = $self->command($body, $who, $type);

	$mess->{body} = $result;
	$self->say(%$mess);

	return;
}

sub help {
	my $self = shift;
	my (@public_and_private, @public, @private);
	my $buffer;

	for my $command (sort keys %commands) {
		if ($commands{$command} & PRIVATE_COMMAND &&
			$commands{$command} & PUBLIC_COMMAND) {
				push @public_and_private, $command;
		}
		elsif ($commands{$command} & PRIVATE_COMMAND) {
			push @private, $command;
		}
		elsif ($commands{$command} & PUBLIC_COMMAND) {
			push @public, $command;
		}
	}

	$buffer .= "Public and Private commands: ".
		(join ', ', @public_and_private) . ' -- ' if
			scalar @public_and_private > 0;
	$buffer .= "Public only commands: ".
		(join ', ', @public) . ' -- ' if
			scalar @public > 0;
	$buffer .= "Private only commands: ".
		join ', ', @private if
			scalar @private > 0;

	return $buffer;
}

sub connected {
	my $self = shift;
	my $cp = CPANPLUS::Backend->new();

	$self->set('cp', $cp);
	$self->set('requests', 0);

	my $c = Net::NNTP->new($SERVER) or die "Cannot open NNTP: $!";
	my ($articles,$low,$high) = $c->group($GROUP) or die "Cannot go to $GROUP: $!";
	$HIGHEST_ARTICLE_NUM = $articles;

	$poe_kernel->state('_reload_indices', $self);
	$poe_kernel->state('_inform_channel_of_new_uploads', $self);
	$poe_kernel->delay_add('_reload_indices', 0);
	$poe_kernel->delay_add('_inform_channel_of_new_uploads', 60);
}

sub _reload_indices {
	my $self = $_[OBJECT];
	my $cp = $self->get('cp');

	$self->log("Reloading indices\n");

	$cp->reload_indices(update_source => 1);
	$poe_kernel->delay_add('_reload_indices', 300);
}

sub _inform_channel_of_new_uploads {
	my $self = $_[OBJECT];
	$self->log("Checking for new CPAN uploads\n");

	my $c = Net::NNTP->new($SERVER) or die "Cannot open NNTP: $!";
	my ($articles,$low,$high) = $c->group($GROUP) or die "Cannot go to $GROUP: $!";
	my $ARTICLES_AT_ITER = $articles;

	for (;$ARTICLES_AT_ITER > $HIGHEST_ARTICLE_NUM && $HIGHEST_ARTICLE_NUM <= $ARTICLES_AT_ITER; $HIGHEST_ARTICLE_NUM++) {
		my $art = $c->article($HIGHEST_ARTICLE_NUM) or next;
		my $mail = Mail::Internet->new($art);

		$mail->tidy_body;
		$self->_parse_article($mail);
	}

	$poe_kernel->delay_add('_inform_channel_of_new_uploads', 60);
}

sub _parse_article {
	my ($self, $mail) = @_;
	my $body = join '', @{$mail->body()};

	return unless $body =~
	m/
		^ The\ (?:URL | uploaded\ file) \s* $ \n
		^ $ \n
		^ \s* (.+) \s* $ \n
		^ $ \n
		^ has\ entered\ CPAN\ as \s* $ \n
		^ $ \n
		^ \s* file: \s (.+) \s* $ \n
		^ \s* size: \s (.+) \s* $ \n
		^ \s* md5: \s (.+) \s* $ \n
		^ $ \n
		^ No\ action\ is\ required\ on\ your\ part \s* $ \n
		^ Request\ entered\ by: \s (.+) \s \( .* \) \s* $ \n
		^ Request\ entered\ on: \s (.+) \s* $ \n
		^ Request\ completed: \s (.+) \s* $ \n
		^ $ \n
		^ .+ $ \n
		^ .+ $
	/mx;

	$mail->{_cpan_file}       = $2;
	$mail->{_cpan_entered_by} = $5;

	return unless $mail->{_cpan_file} =~ /\.tgz$|\.tar\.gz$|\.zip$/;

	($mail->{_cpan_short}) = $mail->{_cpan_file} =~
		/^.+\/(.+)(?:\.tar\.gz$|\.tgz$|\.zip$)/;

	for my $channel ($self->channels()) {
		$self->emote({channel => $channel, body =>
			"upload: $mail->{_cpan_short} by $mail->{_cpan_entered_by}"});
	}
}

sub _get_details {
	my ($self, $module, $type) = @_;
	my $cp = $self->get('cp');
	my $details = $cp->details(modules => [$module]);

	return "No such module: $module" unless $details->ok;
	return $details->rv->{$module}->{$type};
}

sub author {
	my ($self, $module) = @_;
	return $self->_get_details($module, 'Author');
}

sub description {
	my ($self, $module) = @_;
	return $self->_get_details($module, 'Description');
}

sub stage {
	my ($self, $module) = @_;
	return $self->_get_details($module, 'Development Stage');
}

sub style {
	my ($self, $module) = @_;
	return $self->_get_details($module, 'Interface Style');
}

sub language {
	my ($self, $module) = @_;
	return $self->_get_details($module, 'Language Used');
}

sub packapge {
	my ($self, $module) = @_;
	return $self->_get_details($module, 'Package');
}

sub support {
	my ($self, $module) = @_;
	return $self->_get_details($module, 'Support Level');
}

sub version {
	my ($self, $module) = @_;
	return $self->_get_details($module, 'Version on CPAN');
}

sub path {
	my ($self, $module) = @_;
	my $cp = $self->get('cp');
	my $path = $cp->pathname(to => $module);

	return "No such module: $module" unless $path;
	return "\$CPAN/authors/id$path";
}

sub _fork {
	my ($self, $code, $module, $who) = @_;

	my $caller = (caller(1))[3];
	$caller =~ s/.+:://;
	die "'$caller' is not defined as a forkable method\n" unless
		$commands{$caller} & FORK;

	$self->forkit({
		run => $code,
		handler => '_fork_msg_handler',
		body => $module,
		who => $who,
		channel => 'msg',
		arguments => [$self],
	});
}

sub _fork_msg_handler {
	my ($self, $body, $wheel_id) = @_[0, ARG0, ARG1];
	chomp($body);

	# This is not particularly endearing, but it has to be done *sigh*
	my $passthrough_pattern = __PACKAGE__;
	return unless $body =~ /^$passthrough_pattern:\s/;
	$body =~ s/$passthrough_pattern: //;

	my $args = $self->{forks}->{$wheel_id}->{args};
	my $who = $args->{who};
	$self->privmsglow($who, $body);
}

# Why do we do this? Essentially, we are forced to, due to B::B and POE
# semantics. If we don't do this (in conjuction with the passthrough
# related chunk in _fork_msg_handler) the bot will /msg's people with
# internal CPANPLUS debugging info :-(
sub _passthrough {
	shift;
	my $payload = shift;
	print __PACKAGE__ . ": " . $payload . "\n";
}

sub tests {
	my ($self, $module, $who) = @_;

	$self->_fork(
		sub {
			my $module = shift;
			my $self = shift;
			my $cp = $self->get('cp');
			my $report = $cp->reports(modules => [$module]);

			if (not defined $report->rv) {
				$self->_passthrough("No such module: $module");
			}
			elsif (not $report->rv->{$module}) {
				$self->_passthrough("No test results for: $module");
			}
			else {
				$self->_passthrough("--- BEGIN ---");
				for my $rpt (@{$report->rv->{$module}}) {
					$self->_passthrough("$rpt->{grade} $rpt->{platform}");
				}
				$self->_passthrough("--- END ---");
			}
		},
		$module,
		$who,
	);
}

sub details {
	my ($self, $module, $who) = @_;

	$self->_fork(
		sub {
			my $module = shift;
			my $self = shift;
			my $cp = $self->get('cp');
			my $details = $cp->details(modules => [$module]);

			if (not defined $details->rv) {
				$self->_passthrough("No such module: $module");
			}
			else {
				for my $bit
				(   
					'Author', 'Description', 'Development Stage',
					'Interface Style', 'Language Used', 'Package',
					'Support Level', 'Version on CPAN',
				)
				{   
					next if $details->rv->{$module}->{$bit} =~
						/^Unknown|None given$/;
					$self->_passthrough("$bit: " . $details->rv->{$module}->{$bit});
				}
			}
		},
		$module,
		$who,
	);
}

sub modules {
	my ($self, $author, $who) = @_;

	$self->_fork(
		sub {
			my $author = shift;
			my $self = shift;

			if (length $author < 3) {
				$self->_passthrough("Author ID '$author' is too small");
				return;
			}

			my $cp = $self->get('cp');
			my $auth_search = $cp->search(type => 'author', list => [$author],
				authors_only => 1);

			if (not defined $auth_search) {
				$self->_passthrough("No such author: $author");
				return;
			}

			my $modules = $cp->modules(authors => [$author]);

			if (not $modules->rv) {
				$self->_passthrough("Author ID '$author' has no modules");
				return;
			}

			for my $rpt (keys %{$modules->rv->{$author}})
			{   
				$self->_passthrough("$rpt");
			}
		},
		$author,
		$who,
	);
}

sub distributions {
	my ($self, $author, $who) = @_;

	$self->_fork(
		sub {
			my $author = shift;
			my $self = shift;

			if (length $author < 3) {
				$self->_passthrough("Author ID '$author' is too small");
				return;
			}

			my $cp = $self->get('cp');
			my $auth_search = $cp->search(type => 'author', list => [$author],
				authors_only => 1);

			if (not defined $auth_search) {
				$self->_passthrough("No such author: $author");
				return;
			}

			my $distributions = $cp->distributions(authors => [$author]);

			if (not $distributions) {
				$self->_passthrough("Author ID '$author' has no distributions");
				return;
			}

			for my $rpt (keys %{$distributions->rv->{$author}})
			{
				$rpt =~ s/\.tar\.gz$//;
				$rpt =~ s/\.tgz$//;
				$rpt =~ s/\.zip$//;
				$self->_passthrough("$rpt");
			}
		},
		$author,
		$who,
	);

}

sub status {
	my $self = shift;
	my $requests = $self->get('requests');

	return sprintf "%d request%s since I started up at %s",
		$requests, $requests == 1 ? '' : 's', scalar localtime($^T);
}

sub botsnack {
	return "*8-)";
}

sub recent { "Not yet implemented" }
sub fetch { "Not yet implemented" }
sub readme { "Not yet implemented" }

sub url {
	my ($self, $module) = @_;
	my $cp = $self->get('cp');
	my $url = $cp->module_tree->{$module};
	my $buffer = 'http://search.cpan.org/author/';

	return "No such module: $module" unless defined $url;

	my $author  = $url->author();
	my $package = $url->package();

	return "Unable to get url for: $module" unless
		$package =~ s/\.tgz$|\.tar\.gz$|\.zip$//;

	$buffer .= $author . '/' . $package . '/';
	return $buffer;
}

1;
