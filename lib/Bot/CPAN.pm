# $Revision: 1.37 $
# $Id: CPAN.pm,v 1.37 2003/03/23 05:03:36 afoxson Exp $

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
$VERSION = '0.01_07-pre';

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
	my $author = $self->_get_details($event, $module, 'Author');

	return unless $author;

	$self->_print($event, $author);
}

sub botsnack :Public(privmsg) :Args(refuse)
:Help('gives the bot a snack') {
	my ($self, $event) = @_;
	$self->_print($event, ':)');
}

sub _check_author {
	my ($self, $author) = @_;
	my $cp = $self->get('cp');

	$author = uc $author;

	return unless defined $cp->author_tree->{$author};
	return $author;
}

sub _check_module {
	my ($self, $event, $type, $module) = @_;
	my $cp = $self->get('cp');
	my $rv;

	$rv = $self->_check_module_match($type, $module);

	return ($rv, $module, 1) if $rv;

	my $search = $cp->search(type => 'module', list => [qr/^$module$/i]);
	my @cache;

	for my $key (keys %{$search}) {
		push @cache, $key;
	}

	if (scalar @cache == 1) {
		$rv = $self->_check_module_match($type, $cache[0]);
		return ($rv, $cache[0], 2) if $rv;
	}

	my @recent = @{$self->get('recent')};
	for my $recent (@recent) {
		$recent =~ s/-/::/g;
		$recent =~ s/::\d.+//g;

		if ($recent eq $module) {
			$self->_print($event,
				"$module is a brand new distribution. I'll have details shortly.");
			return;
		}
	}

	$type eq 'readme' ?
		$self->_print($event, "No such module (or readme): $module") :
		$self->_print($event, "No such module: $module");
	return;
}

sub _check_module_match {
	my ($self, $type, $module) = @_;
	my $cp = $self->get('cp');
	my $rv;

	if ($type eq 'details') {
		$rv = $cp->details(modules => [$module]);
		return $rv if $rv->ok;
	}
	elsif ($type eq 'module_tree') {
		$rv = $cp->module_tree->{$module};
		return $rv if defined $rv;
	}
	elsif ($type eq 'pathname') {
		$rv = $cp->pathname(to => $module);
		return $rv if $rv;
	}
	elsif ($type eq 'readme') {
		$rv = $cp->readme(modules => [$module]);
		return $rv if $rv->ok;
	}
	elsif ($type eq 'reports') {
		$rv = $cp->reports(modules => [$module]);
		return $rv if defined $rv->rv;
	}   

	return;
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
	if (exists $chanpol->{allow} and $inform =~ /$chanpol->{allow}/) {
		return 1;
	}
	elsif (exists $chanpol->{deny} and $inform =~ /$chanpol->{deny}/) {
		return 0;
	}

	return 1;
}

sub config :Private(notice) :Args(refuse) :Admin :LowPrio
:Help('Shows the bots configuration') {
	my ($self, $event) = @_;

	$self->_print($event, 'Adminhost: ' . $self->get('adminhost'));
	$self->_print($event, 'Alt Nicks: ' . join ', ', $self->alt_nicks) if
		scalar $self->alt_nicks > 0;
	$self->_print($event, 'Channels: ' . join ', ', $self->channels);
	$self->_print($event, 'Ignore List: ' . join ', ', $self->ignore_list) if
		scalar $self->ignore_list > 0;
	$self->_print($event, 'Debug: ' . $self->debug);
	$self->_print($event, 'Group: ' . $self->get('group'));
	$self->_print($event, 'Inform Channel of New Uploads Interval: ' .
		$self->get('inform_channel_of_new_uploads'));
	$self->_print($event, 'Name: ' . $self->name);
	$self->_print($event, 'News Server: ' . $self->get('news_server'));
	$self->_print($event, 'Nick: ' . $self->nick);
	$self->_print($event, 'Port: ' . $self->port);
	$self->_print($event, 'Reload Indice Interval: ' .
		$self->get('reload_indices_interval'));
	$self->_print($event, 'Search Max Results: ' .
		$self->get('search_max_results'));
	$self->_print($event, 'Servers: ' . join ', ', $self->servers);
	$self->_print($event, 'Username: ' . $self->username);
}

# this is called the moment we successfully connect to a server
sub connected {
	my $self = shift;
	my $cp = CPANPLUS::Backend->new() unless $self->get('cp');

	$self->set('cp', $cp) unless $self->get('cp');
	$self->set('requests', 0) unless $self->get('requests');
	$self->set('recent', []) unless $self->get('recent') and
		ref $self->get('recent') eq 'ARRAY';

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
	my $description = $self->_get_details($event, $module, 'Description');

	return unless $description;

	$self->_print($event, $description);
}

sub details :Private(notice) :Fork :LowPrio :Args(required)
:Help('retrieves full details of a module') {
	my ($self, $event, $module) = @_;
	my ($details, $actual) = $self->_check_module($event, 'details', $module);
	return unless $details;

	for my $bit (   
		'Author', 'Description', 'Development Stage', 'Interface Style',
		'Language Used', 'Package', 'Support Level', 'Version on CPAN',
	)
	{   
		next if $details->rv->{$actual}->{$bit} =~ /^Unknown|None given$/;
		$self->_print($event, "$bit: " . $details->rv->{$actual}->{$bit});
	}
}

sub distributions :Private(notice) :Fork :LowPrio :Args(required)
:Help('retrieves all of the distributions by an author') {
	my ($self, $event, $author) = @_;
	my $cp = $self->get('cp');
	my $actual_author = $self->_check_author($author);

	if (not $actual_author) {
		$self->_print($event, "No such author: $author");
		return;
	}

	my $distributions = $cp->distributions(authors => [$actual_author]);

	if (not $distributions) {
		$self->_print($event, "Author '$actual_author' has no distributions");
		return;
	}

	for my $rpt (keys %{$distributions->rv->{$actual_author}})
	{
		$rpt =~ s/\.tar\.gz$//;
		$rpt =~ s/\.tgz$//;
		$rpt =~ s/\.zip$//;
		$self->_print($event, "$rpt");
	}
}

sub dlurl :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the download url of a module') {
	my ($self, $event, $module) = @_;
	my ($details) = $self->_check_module($event, 'module_tree', $module);
	return unless $details;

	my $path = $details->path;
	my $package = $details->package;
	my $buffer = 'http://search.cpan.org/CPAN/authors/id/';

	$buffer .= $path . '/' . $package;
	$self->_print($event, $buffer);
}

sub _get_details {
	my ($self, $event, $module, $type) = @_;
	my ($details, $actual, $rv) =
		$self->_check_module($event, 'details', $module);
	return unless $details;

	if ($rv == 1) {
		return $details->rv->{$actual}->{$type};
	}
	elsif ($rv == 2) {
		my $type_string = $type;
		$type_string = lc $type_string;
		$type_string =~ s/cpan/CPAN/;

		(substr $actual, -1, 1) =~ /^s$/i ?
			return "${actual}' $type_string is: ${\($details->rv->{$actual}->{$type})}" :
			return "${actual}'s $type_string is: ${\($details->rv->{$actual}->{$type})}";
	}
}

sub help :Private(notice) :LowPrio :Args(optional)
:Help('provides instruction on how to use this bot') {
	my ($self, $event, $command) = @_;
	my (@public_and_private, @public, @private);

	if (not $command) {
		$self->_print($event, $self->nick() . ' is brought to you by ' .
			__PACKAGE__ . " version $VERSION");

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
	my $language = $self->_get_details($event, $module, 'Language Used');

	return unless $language;

	$self->_print($event, $language);
}

sub modules :Private(notice) :Fork :LowPrio :Args(required)
:Help('retrieves the modules created by a given author') {
	my ($self, $event, $author) = @_;
	my $cp = $self->get('cp');
	my $actual_author = $self->_check_author($author);

	unless ($actual_author) {
		$self->_print($event, "No such author: $author");
		return;
	}

	my $modules = $cp->modules(authors => [$actual_author]);

	if (not $modules->rv) {
		$self->_print($event, "Author ID '$actual_author' has no modules");
		return;
	}

	for my $rpt (keys %{$modules->rv->{$actual_author}})
	{   
		$self->_print($event, "$rpt");
	}
}

sub package :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the package of a module') {
	my ($self, $event, $module) = @_;
	my $package = $self->_get_details($event, $module, 'Package');

	return unless $package;

	$self->_print($event, $package);
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
	my ($path) = $self->_check_module($event, 'pathname', $module);
	return unless $path;

	$self->_print($event, "\$CPAN/authors/id$path");
}

sub readme :Public(privmsg) :Private(notice) :Args(required)
:Help('sends readme for module via DCC CHAT') {
	my ($self, $event, $module) = @_;
	my ($readme, $actual) = $self->_check_module($event, 'readme', $module);
	return unless $readme;

	my $who = $event->{who};

	$self->set("readme_$who", $actual);
	$self->_print($event, "Sending readme for $actual..");
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
	my ($url, $actual) = $self->_check_module($event, 'module_tree', $module);
	return unless $url;

	my $buffer = 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=';
	my $package = $url->package();

	unless ($package =~ s/\.tgz$|\.tar\.gz$|\.zip$//) {
		$self->_print($event, "Unable to get url for: $actual");
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
	my $stage = $self->_get_details($event, $module, 'Development Stage');

	return unless $stage;

	$self->_print($event, $stage);
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
	my $style = $self->_get_details($event, $module, 'Interface Style');

	return unless $style;

	$self->_print($event, $style);
}

sub support :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the support level of a module') {
	my ($self, $event, $module) = @_;
	my $support = $self->_get_details($event, $module, 'Support Level');

	return unless $support;

	$self->_print($event, $support);
}

sub tests :Private(notice) :Fork :LowPrio :Args(required)
:Help('retrieves the test reports of a module') {
	my ($self, $event, $module) = @_;
	my ($report, $actual) = $self->_check_module($event, 'reports', $module);
	return unless $report;

	if (not $report->rv->{$actual}) {
		$self->_print($event, "No test reports for: $actual");
	}
	else {
		$self->_print($event, sprintf "%d test report%s for $actual",
			scalar @{$report->rv->{$actual}},
			@{$report->rv->{$actual}} == 1 ? '' : 's');

		for my $rpt (@{$report->rv->{$actual}}) {
			$self->_print($event, "$rpt->{grade} $rpt->{platform}");
		}
	}
}

sub url :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the www path to a module') {
	my ($self, $event, $module) = @_;
	my ($url, $actual) = $self->_check_module($event, 'module_tree', $module);
	return unless $url;

	my $buffer = 'http://search.cpan.org/author/';
	my $author  = $url->author();
	my $package = $url->package();

	unless ($package =~ s/\.tgz$|\.tar\.gz$|\.zip$//) {
		$self->_print($event, "Unable to get url for: $actual");
		return;
	}

	$buffer .= $author . '/' . $package . '/';
	$self->_print($event, $buffer);
}

sub version :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the latest version of a module') {
	my ($self, $event, $module) = @_;
	my $version = $self->_get_details($event, $module, 'Version on CPAN');

	return unless $version;

	$self->_print($event, $version);
}

sub whois :Private(notice) :Public(privmsg) :Args(required)
:Help('gets an author's name and email from a CPAN ID') {
	my ($self, $event, $author) = @_;
	my $cp = $self->get('cp');
	my $actual_author = $self->_check_author($author);

	unless ($actual_author) {
		$self->_print($event, "No such author: $author");
		return;
	}

	my $cpanauthor = $cp->author_tree->{$actual_author};
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
		$self->log("$who requested a DCC CHAT, but I've no matching readme\n");
		return;
	}

	my $readme = $cp->readme(modules => [$module]);
	my $length = length($readme->rv->{$module});

	$self->log("Sending $who readme for $module ($length)\n");
	$self->delete("readme_$who");
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

sub irc_disconnected_state { 
	my ($this, $server) = @_[OBJECT, ARG0];
	$this->log("Lost connection to server $server.\n");
	$poe_kernel->delay('_reload_indices' => undef);
	$poe_kernel->delay('_inform_channel_of_new_uploads' => undef);
	$poe_kernel->delay('reconnect' => 60);
}

sub irc_error_state { 
	my ($this, $err) = @_[OBJECT, ARG0];
	$this->log("Server error occurred! $err\n");
	$poe_kernel->delay('_reload_indices' => undef);
	$poe_kernel->delay('_inform_channel_of_new_uploads' => undef);
	$poe_kernel->delay('reconnect' => 60);
}

sub irc_socketerr_state {
	my ($this, $err) = @_[OBJECT, ARG0];
	$this->log("Socket error occurred: $err\n");
	$poe_kernel->delay('_reload_indices' => undef);
	$poe_kernel->delay('_inform_channel_of_new_uploads' => undef);
	$poe_kernel->delay('reconnect' => 60);
}

1;
