# $Revision: 1.23 $
# $Id: CPAN.pm,v 1.23 2003/03/17 05:22:14 afoxson Exp $

# Bot::CPAN - provides CPAN services via IRC
# Copyright (c) 2003 Adam J. Foxson. All rights reserved.
# Copyright (c) 2003 Casey West. All rights reserved.

# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Bot::CPAN;

require 5.006;

use strict;
use Net::NNTP; 
use Mail::Internet;
use POE;
use CPANPLUS::Backend;
use Bot::CPAN::Glue;
use vars qw(@ISA $VERSION);

@ISA = qw(Bot::CPAN::Glue);
$VERSION = '0.01_06';

local $^W;

sub _add_to_recent {
	my ($self, $dist) = @_;
	my @recent = @{$self->get('recent')};

	shift @recent if scalar @recent == 10;
	push @recent, $dist;

	$self->set('recent', \@recent);
}

sub author :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the author of a module') {
	my ($self, $event, $module) = @_;
	$self->_print($event, $self->_get_details($module, 'Author'));
}

sub botsnack :Public(privmsg) :Args(refuse)
:Help('gives the bot a snack') {
	my ($self, $event) = @_;
	$self->_print($event, ':)');
}

sub _check_policy {
	my ($self, $channel, $inform) = @_;
	my $policy = $self->get('policy'); # by default is {}

	# we are guaranteed that the policy "exists", internally speaking..
	# but if it's not defined, allow all
	return 1 unless defined $policy;

	# empty policy? allow all
	return 1 unless scalar keys %{$policy} > 0;

	# non-existant channel policy? allow all
	return 1 unless exists $policy->{$channel};

	my $chanpol = $policy->{$channel};

	# undefined channel policy? allow all
	return 1 unless defined $chanpol;

	# empty channel policy? allow all
	return 1 unless scalar keys %{$chanpol} > 0;

	# we can assume that if an allow/deny exists it is defined
	if (exists $chanpol->{allow} and $inform =~ /$chanpol->{allow}/i) {
		return 1;
	}
	elsif (exists $chanpol->{deny} and $inform =~ /$chanpol->{deny}/i) {
		return 0;
	}

	return 1;
}

# this is called the moment we successfully connect to a server
sub connected {
	my $self = shift;
	my $cp = CPANPLUS::Backend->new();

	$self->set('cp', $cp);
	$self->set('requests', 0);
	$self->set('recent', []);

	my $nntp = Net::NNTP->new($self->get('news_server')) or
		die "Cannot open NNTP server: $!";
	my ($articles) = ($nntp->group($self->get('group')))[0] or
		die "Cannot go to group: $!";
	$self->set('articles', $articles + 1);

	$poe_kernel->state('irc_dcc_start', $self);
	$poe_kernel->state('_reload_indices', $self);
	$poe_kernel->state('_inform_channel_of_new_uploads', $self);
	$poe_kernel->delay_add('_reload_indices', 0);
	$poe_kernel->delay_add('_inform_channel_of_new_uploads',
		$self->get('inform_channel_of_new_uploads'));
}

sub description :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the description of a module') {
	my ($self, $event, $module) = @_;
	$self->_print($event, $self->_get_details($module, 'Description'));
}

sub details :Private(notice) :Fork :LowPrio :Args(required)
:Help('retrieves full details of a module') {
	my ($self, $event, $module) = @_;
	my $cp = $self->get('cp');
	my $details = $cp->details(modules => [$module]);

	if (not defined $details->rv) {
		$self->_print($event, "No such module: $module");
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
			$self->_print($event, "$bit: " . $details->rv->{$module}->{$bit});
		}
	}
}

sub distributions :Private(notice) :Fork :LowPrio :Args(required)
:Help('retrieves all of the distributions by an author') {
	my ($self, $event, $author) = @_;

	$author = uc $author;

	if (length $author < 3) {
		$self->_print($event, "Author ID '$author' is too small");
		return;
	}

	my $cp = $self->get('cp');
	my $auth_search = $cp->search(type => 'author', list => [$author],
		authors_only => 1);

	if (not defined $auth_search) {
		$self->_print($event, "No such author: $author");
		return;
	}

	my $distributions = $cp->distributions(authors => [$author]);

	if (not $distributions) {
		$self->_print($event, "Author ID '$author' has no distributions");
		return;
	}

	for my $rpt (keys %{$distributions->rv->{$author}})
	{
		$rpt =~ s/\.tar\.gz$//;
		$rpt =~ s/\.tgz$//;
		$rpt =~ s/\.zip$//;
		$self->_print($event, "$rpt");
	}
}

sub _get_details {
	my ($self, $module, $type) = @_;
	my $cp = $self->get('cp');
	my $details = $cp->details(modules => [$module]);

	return "No such module: $module" unless $details->ok;
	return "No such module: $module" unless
		$details->rv->{$module}->{$type};
	return $details->rv->{$module}->{$type};
}

sub help :Private(notice) :LowPrio :Args(optional)
:Help('provides instruction on how to use this bot') {
	my ($self, $event, $command) = @_;
	my (@public_and_private, @public, @private);

	$self->_print($event, $self->nick() . ' is brought to you by ' .
		__PACKAGE__ . " version $VERSION");

	if (not $command) {
		for my $command (sort $self->_commands()) {
			if ($self->_private_command($command) &&
				$self->_public_command($command)) {
					push @public_and_private, $command;
			}
			elsif ($self->_private_command($command)) {
				push @private, $command;
			}
			elsif ($self->_public_command($command)) {
				push @public, $command;
			}
		}

		$self->_print($event, "Public and Private commands: ".
			(join ', ', @public_and_private)) if scalar @public_and_private > 0;
		$self->_print($event, "Public only commands: ".
			(join ', ', @public)) if scalar @public > 0;
		$self->_print($event, "Private only commands: ".
			(join ', ', @private)) if scalar @private > 0;
	}
	else {
		$self->_print($event, $self->_help($command));
	}
}

sub language :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the language of a module') {
	my ($self, $event, $module) = @_;
	$self->_print($event, $self->_get_details($module, 'Language Used'));
}

sub modules :Private(notice) :Fork :LowPrio :Args(required)
:Help('retrieves the modules created by a given author') {
	my ($self, $event, $author) = @_;

	$author = uc $author;

	if (length $author < 3) {
		$self->_print($event, "Author ID '$author' is too small");
		return;
	}

	my $cp = $self->get('cp');
	my $auth_search = $cp->search(type => 'author', list => [$author],
		authors_only => 1);

	if (not defined $auth_search) {
		$self->_print($event, "No such author: $author");
		return;
	}

	my $modules = $cp->modules(authors => [$author]);

	if (not $modules->rv) {
		$self->_print($event, "Author ID '$author' has no modules");
		return;
	}

	for my $rpt (keys %{$modules->rv->{$author}})
	{   
		$self->_print($event, "$rpt");
	}
}

sub package :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the package of a module') {
	my ($self, $event, $module) = @_;
	$self->_print($event, $self->_get_details($module, 'Package'));
}

sub _parse_article {
	my ($self, $mail) = @_;
	my $body = join '', @{$mail->body()};

	return 1 unless $body =~
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

	return 2 unless $mail->{_cpan_file} =~ /\.tgz$|\.tar\.gz$|\.zip$/;

	($mail->{_cpan_short}) = $mail->{_cpan_file} =~
		/^.+\/(.+)(?:\.tar\.gz$|\.tgz$|\.zip$)/;

	$self->_add_to_recent($mail->{_cpan_short});

	my $inform = "$mail->{_cpan_short} by $mail->{_cpan_entered_by}";
	my $chan_inform = "upload: $inform";

	for my $channel ($self->channels()) {
		$self->emote({channel => $channel, body => $chan_inform}) if
			$self->_check_policy($channel, $inform);
	}

	return;
}

sub path :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the full CPAN path of a module') {
	my ($self, $event, $module) = @_;
	my $cp = $self->get('cp');
	my $path = $cp->pathname(to => $module);

	unless ($path) {
		$self->_print($event, "No such module: $module");
		return;
	}

	$self->_print($event, "\$CPAN/authors/id$path");
}

sub readme :Public(privmsg) :Private(notice) :Args(required)
:Help('sends README for module via DCC CHAT') {
	my ($self, $event, $module) = @_;
	my $cp = $self->get('cp');
	my $mod = $cp->module_tree->{$module};

	unless (defined $mod) {
		$self->_print($event, "No such module: $module");
		return;
	}

	my $readme = $cp->readme(modules => [$module]);

	unless ($readme->ok) {
		$self->_print($event, "No README for: $module");
		return;
	}

	my $who = $event->{who};

	$self->set("readme_$who", $module);
	$self->_print($event, "Sending..");
	$self->dcc($who, 'CHAT');
}

sub recent :Private(notice) :Public(privmsg) :Args(refuse)
:Help('shows last ten distributions uploaded to the CPAN') {
	my ($self, $event) = @_;
	my @recent = @{$self->get('recent')};

	if (scalar @recent < 1) {
		$self->_print($event, "I just got here. Give me a bit to get settled. :)");
		return;
	}

	$self->_print($event, join ', ', (reverse @recent));
}

sub rt :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the RT www path to a module') {
	my ($self, $event, $module) = @_;
	my $cp = $self->get('cp');
	my $url = $cp->module_tree->{$module};
	my $buffer = 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=';

	unless (defined $url) {
		$self->_print($event, "No such module: $module");
		return;
	}

	my $package = $url->package();

	unless ($package =~ s/\.tgz$|\.tar\.gz$|\.zip$//) {
		$self->_print($event, "Unable to get url for: $module");
		return;
	}

	$buffer .= $package;
	$self->_print($event, $buffer);
}

sub search :Private(notice) :Args(required) :LowPrio
:Help('returns modules that match a regex') {
	my ($self, $event, $module) = @_;
	my $cp = $self->get('cp');
	my $mod_search = $cp->search(type => 'module', list => [$module]);
	my @cache = ();

	for my $key (keys %{$mod_search}) {
		push @cache, $key;
	}

	if (scalar @cache > $self->get('search_max_results')) {
		$self->_print($event, "Too many matches (${\(scalar @cache)} > ${\($self->get('search_max_results'))}). Be more specific please");
	}
	elsif (scalar @cache == 0) {
		$self->_print($event, "No matches");
	}
	else {
		for my $key (sort @cache) {
			$self->_print($event, $key);
		}
	}
}

sub stage :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the stage of a module') {
	my ($self, $event, $module) = @_;
	$self->_print($event, $self->_get_details($module, 'Development Stage'));
}

sub status :Private(notice) :Public(privmsg) :Args(refuse)
:Help('retrieves the status of the bot') {
	my ($self, $event) = @_;
	my $requests = $self->get('requests');

	$self->_print($event, sprintf "%d request%s since I started up at %s",
		$requests, $requests == 1 ? '' : 's', scalar localtime($^T));
}

sub style :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the style of a module') {
	my ($self, $event, $module) = @_;
	$self->_print($event, $self->_get_details($module, 'Interface Style'));
}

sub support :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the support level of a module') {
	my ($self, $event, $module) = @_;
	$self->_print($event, $self->_get_details($module, 'Support Level'));
}

sub tests :Private(notice) :Fork :LowPrio :Args(required)
:Help('retrieves the test results of a module') {
	my ($self, $event, $module) = @_;
	my $cp = $self->get('cp');
	my $report = $cp->reports(modules => [$module]);

	if (not defined $report->rv) {
		$self->_print($event, "No such module: $module");
	}
	elsif (not $report->rv->{$module}) {
		$self->_print($event, "No test results for: $module");
	}
	else {
		for my $rpt (@{$report->rv->{$module}}) {
			$self->_print($event, "$rpt->{grade} $rpt->{platform}");
		}
	}
}

sub url :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the www path to a module') {
	my ($self, $event, $module) = @_;
	my $cp = $self->get('cp');
	my $url = $cp->module_tree->{$module};
	my $buffer = 'http://search.cpan.org/author/';

	unless (defined $url) {
		$self->_print($event, "No such module: $module");
		return;
	}

	my $author  = $url->author();
	my $package = $url->package();

	unless ($package =~ s/\.tgz$|\.tar\.gz$|\.zip$//) {
		$self->_print($event, "Unable to get url for: $module");
		return;
	}

	$buffer .= $author . '/' . $package . '/';
	$self->_print($event, $buffer);
}

sub version :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the latest version of a module') {
	my ($self, $event, $module) = @_;
	$self->_print($event, $self->_get_details($module, 'Version on CPAN'));
}

sub whois :Private(notice) :Public(privmsg) :Args(required)
:Help('gets an author's name and email from a CPAN ID') {
	my ($self, $event, $author) = @_;
	my $cp = $self->get('cp');
	my $cpanauthor = $cp->author_tree->{$author};

	unless (defined $cpanauthor) {
		$self->_print($event, "No such CPAN ID: $author");
		return;
	}

	my $name = $cpanauthor->name;
	my $email = $cpanauthor->email || 'no email';

	$self->_print($event, "$name ($email)");
}

# special timed event handlers below

sub _inform_channel_of_new_uploads {
	my $self = $_[OBJECT];
	my $nntp = Net::NNTP->new($self->get('news_server'));
	my ($articles) = ($nntp->group($self->get('group')))[0] if defined $nntp;

	if (defined $nntp and defined $articles) {
		my $old_articles = $self->get('articles');
		my ($match, $no_body_match, $no_filename_match, $checked) =
			(0, 0, 0, 0);

		if ($articles >= $old_articles) {
			$self->set('articles', $articles + 1);

			for my $article ($old_articles .. $articles) {
				my $article_data;

				unless ($article_data = $nntp->article($article)) {
					$self->log("Unable to retrieve article # $article\n");
					next;
				} 

				my $mail = Mail::Internet->new($article_data);
				$mail->tidy_body;
				my $retval = $self->_parse_article($mail);

				if (not $retval) { $match++ }
				elsif ($retval == 1) { $no_body_match++ }
				elsif ($retval == 2) { $no_filename_match++ }
				$checked++;
			}
		}

		$self->log(sprintf "%d new article%s, %d match%s, %d reject%s/filename, %d reject%s/body\n", $checked, $checked == 1 ? '' : 's', $match, $match == 1 ? '' : 'es', $no_filename_match, $no_filename_match == 1 ? '' : 's', $no_body_match, $no_body_match == 1 ? '' : 's');
	}
	else {
		$self->log("Unable to check for new uploads: ${\($! ? $! : '?')}\n");
	}

	$poe_kernel->delay_add('_inform_channel_of_new_uploads',
		$self->get('inform_channel_of_new_uploads'));
}

sub irc_dcc_start
{
	my ($self, $magic, $who, $type) = @_[OBJECT, ARG0, ARG1, ARG2];

	unless ($type =~ /CHAT/i) {
		$self->log("Got an invalid DCC request from $who\n");
		return;
	}

	my $cp = $self->get('cp');
	my $module = $self->get("readme_$who");

	unless ($module) {
		$self->log("$who requested a DCC CHAT, but I've no matching README\n");
		return;
	}

	my $readme = $cp->readme(modules => [$module]);
	my $length = length($readme->rv->{$module});

	$self->log("Sending $who README for $module ($length)\n");
	$self->set("readme_$who", '');
	$self->dcc_chat($magic, $readme->rv->{$module});
}

sub _reload_indices {
	my $self = $_[OBJECT];

	$self->forkit({
		run => sub {
			my $self = shift;
			my $cp = $self->get('cp');

			$cp->reload_indices(update_source => 1);
		},
		handler => '_fork_handler',
		body => $self,
	});
	$poe_kernel->delay_add('_reload_indices',
		$self->get('reload_indices_interval'));
}

1;
