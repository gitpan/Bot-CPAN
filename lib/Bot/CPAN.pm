# $Revision: 1.7 $
# $Id: CPAN.pm,v 1.7 2003/08/28 09:32:32 afoxson Exp $
#
# Bot::CPAN - provides CPAN services via IRC
# Copyright (c) 2003 Adam J. Foxson. All rights reserved.
# Copyright (c) 2003 Casey West. All rights reserved.

# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.

package Bot::CPAN;

require 5.006;

use strict;
use vars qw(@ISA $VERSION);
use Bot::CPAN::Glue;
use CPANPLUS::Backend;
use LWP::UserAgent;
use Mail::Internet;
use Math::Round;
use Net::NNTP; 
use POE;
use Statistics::Descriptive;
use URI;
use XML::RSS::Parser;

@ISA = qw(Bot::CPAN::Glue);
($VERSION) = '$Revision: 1.7 $' =~ /\s+(\d+\.\d+)\s+/;

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

	$self->_print($event, $self->phrase({author => $author}));
}

sub botsnack :Public(privmsg) :Args(refuse)
:Help('gives the bot a snack') {
	my ($self, $event) = @_;
	$self->_print($event, $self->phrase());
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
			$self->_print($event, $self->phrase('new', {module => $module}));
			return;
		}
	}

	$type eq 'readme' ?
		$self->_print($event, $self->phrase('readme', {module => $module})) :
		$self->_print($event, $self->phrase('NO_MODULE', {module => $module}));
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

	$self->_print($event, $self->phrase('adminhost',
		{adminhost => $self->get('adminhost')}));
	$self->_print($event, $self->phrase('alt_nicks',
		{alt_nicks => join ', ', $self->alt_nicks})) if
			scalar $self->alt_nicks > 0;
	$self->_print($event, $self->phrase('channels',
		{channels => join ', ', $self->channels}));
	$self->_print($event, $self->phrase('ignore_list',
		{ignore_list=> join ', ', $self->ignore_list})) if
			scalar $self->ignore_list > 0;
	$self->_print($event, $self->phrase('debug',
		{debug => $self->debug}));
	$self->_print($event, $self->phrase('group',
		{group => $self->get('group')}));
	$self->_print($event, $self->phrase('inform_channel_of_new_uploads',
		{inform_channel_of_new_uploads =>
			$self->get('inform_channel_of_new_uploads')}));
	$self->_print($event, $self->phrase('name',
		{name => $self->name}));
	$self->_print($event, $self->phrase('news_server',
		{news_server => $self->get('news_server')}));
	$self->_print($event, $self->phrase('nick',
		{nick => $self->nick}));
	$self->_print($event, $self->phrase('port',
		{port => $self->port}));
	$self->_print($event, $self->phrase('reload_indices_interval',
		{reload_indices_interval => $self->get('reload_indices_interval')}));
	$self->_print($event, $self->phrase('search_max_results',
		{search_max_results => $self->get('search_max_results')}));
	$self->_print($event, $self->phrase('servers',
		{servers => join ', ', $self->servers}));
	$self->_print($event, $self->phrase('username',
		{username => $self->username}));
	$self->_print($event, $self->phrase('last_indice_reload',
		{last_indice_reload => $self->get('last_indice_reload')}));
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
	$poe_kernel->delay('reconnect');
	$poe_kernel->delay_add('_reload_indices', 0);
	$poe_kernel->delay_add('_inform_channel_of_new_uploads',
		$self->get('inform_channel_of_new_uploads'));
}

sub description :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the description of a module') {
	my ($self, $event, $module) = @_;

	if (eval{require Module::CPANTS}) {
		my $package = $self->_get_details($event, $module, 'Package');
		return unless $package;
		my $c = Module::CPANTS->new();
		my $cpants = $c->data;
		my $data = $cpants->{$package};
		my $desc = $data->{'description'};
		if ($desc) {
			$self->_print($event, $self->phrase({description => $desc}));
			return;
		}
	}

	my $description = $self->_get_details($event, $module, 'Description');

	return unless $description;

	$self->_print($event, $self->phrase({description => $description}));
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
		$self->_print($event,
			$self->phrase({label => $bit, value => $details->rv->{$actual}->{$bit}}));
	}
}

sub distributions :Private(notice) :Fork :LowPrio :Args(required)
:Help('retrieves all of the distributions by an author') {
	my ($self, $event, $author) = @_;
	my $cp = $self->get('cp');
	my $actual_author = $self->_check_author($author);

	unless ($actual_author) {
		$self->_print($event, $self->phrase('NO_AUTHOR', {author => $author}));
		return;
	}

	my $distributions = $cp->distributions(authors => [$actual_author]);

	unless ($distributions->rv) {
		$self->_print($event, $self->phrase('no', {actual_author => $actual_author}));
		return;
	}

	for my $rpt (keys %{$distributions->rv->{$actual_author}})
	{
		$rpt =~ s/\.tar\.gz$//;
		$rpt =~ s/\.tgz$//;
		$rpt =~ s/\.zip$//;
		$self->_print($event, $self->phrase('yes', {rpt => "$rpt"}));
	}
}

sub docurl :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the url of a module's documentation') {
	my ($self, $event, $module) = @_;
	my ($url, $actual) = $self->_check_module($event, 'module_tree', $module);
	return unless $url;

	my $buffer = "http://search.cpan.org/perldoc?$module";

	$self->_print($event, $self->phrase({buffer => $buffer}));
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
	$self->_print($event, $self->phrase({buffer => $buffer}));
}

# from TUCS, coded by gbarr and from acme's CPAN::WWW::Testers
sub _extract_name_version {
	my($self, $distvers) = @_;

	my ($dist, $version) = $distvers =~ /^
		((?:[-+.]*(?:[A-Za-z0-9]+|(?<=\D)_|_(?=\D))*
		(?:
		[A-Za-z](?=[^A-Za-z]|$)
		|
		\d(?=-)
		)(?<![._-][vV])
		)+)(.*)
	$/xs or return;

	$version = $1
	if !length $version and $dist =~ s/-(\d+\w)$//;

	$version = $1 . $version
	if $version =~ /^\d+$/ and $dist =~ s/-(\w+)$//;

	if ($version =~ /\d\.\d/) {
		$version =~ s/^[-_.]+//;
	}
	else {
		$version =~ s/^[-_]+//;
	}

	return $dist;
}

sub _get_cpanratings {
	shift;
	my $type = shift;
	my $module = shift;
	my $ua = LWP::UserAgent->new(agent => "Bot::CPAN/$VERSION");
	my $place;

	if ($type eq 'reviews') {
		$place = "http://cpanratings.perl.org/d/$module.rss";
	}
	elsif ($type eq 'ratings') {
		$place = "http://cpanratings.perl.org/d/$module";
	}

	my $url = URI->new($place);
	my $req = HTTP::Request->new(GET => $url);
	my $data = $ua->request($req);

	return $data;
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

sub _get_karma {
	my $self = shift;
	my $module = shift;
	my $ratestr = ''; # (unknown)
	my $dist = $self->_extract_name_version($module);

	if (eval{require Socket; Socket::inet_aton('cpanratings.perl.org')}) {
		my $data = $self->_get_cpanratings('ratings', $dist); 
		if ($data->is_success) {
			my @data = split /\n/, $data->as_string;
			my @ratings;

			for my $rating (@data) {
				if ($rating =~ m!<img src="/images/stars-(\d.\d).png">!) {
					push @ratings, $1;
				}
			}

			if (scalar @ratings == 0) {
				$ratestr = ''; # (unrated)
			}
			else {
				my $stat = Statistics::Descriptive::Full->new();
				$stat->add_data(@ratings);
				my $round = round($stat->mean());

				$ratestr = '(';
				$ratestr .= '+' x $round;
				$ratestr .= ' ' x (5-$round);
				$ratestr .= ')';

				$ratestr = '' if length($ratestr) != 7; # (error)
			}
		}
		else {
			$ratestr = ''; # (unrated)
		}
	}

	return $ratestr;
}

sub help :Private(notice) :LowPrio :Args(optional)
:Help('provides instruction on how to use this bot') {
	my ($self, $event, $command) = @_;
	my (@public_and_private, @public, @private);

	unless ($command) {
		$self->_print($event, $self->phrase('by',
			{nick => $self->nick(), pkg => __PACKAGE__, vers => $VERSION}));

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

		$self->_print($event, $self->phrase('both',
			{commands => (join ', ', @public_and_private)})) if
				scalar @public_and_private > 0;
		$self->_print($event, $self->phrase('channel',
			{commands => (join ', ', @public)})) if
				scalar @public > 0;
		$self->_print($event, $self->phrase('msg',
			{commands => (join ', ', @private)})) if scalar @private > 0;
	}
	else {
		$self->_print($event,
			$self->phrase('help', {help => $self->_help($command)}));
	}
}

sub language :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the language of a module') {
	my ($self, $event, $module) = @_;
	my $language = $self->_get_details($event, $module, 'Language Used');

	return unless $language;

	$self->_print($event, $self->phrase({language => $language}));
}

sub _module_to_dist {
	my $self = shift;
	my $module = shift;
	my $cp = $self->get('cp');
	my $mod = $cp->module_tree->{$module} || return $module;
	my $pkg = $mod->package;

	unless ($pkg =~ s/\.tgz$|\.tar\.gz$|\.zip$//) {
		return $module;
	}

	return $pkg;
}

sub modulelist :Private(notice) :Public(privmsg) :Args(required)
:Help('determines if a given module is in the Module List') {
	my ($self, $event, $module) = @_;
	my $cp = $self->get('cp');
	my $details = $cp->details(modules => [$module]);

	unless ($details->ok) {
		$self->_print($event, $self->phrase('NO_MODULE', {module => $module}));
		return;
	}

	my $desc = $details->rv->{$module}->{'Description'};
	my $dev = $details->rv->{$module}->{'Development Stage'};
	my $interface = $details->rv->{$module}->{'Interface Style'};
	my $lang = $details->rv->{$module}->{'Language Used'};
	my $support = $details->rv->{$module}->{'Support Level'};

	if ($desc eq 'None given' and $dev eq 'Unknown' and
		$interface eq 'Unknown' and $lang eq 'Unknown' and
		$support eq 'Unknown') {
		$self->_print($event, $self->phrase('no', {module => $module}));
	}
	else {
		$self->_print($event, $self->phrase('yes', {module => $module}));
	}
}

sub modules :Private(notice) :Fork :LowPrio :Args(required)
:Help('retrieves the modules created by a given author') {
	my ($self, $event, $author) = @_;
	my $cp = $self->get('cp');
	my $actual_author = $self->_check_author($author);

	unless ($actual_author) {
		$self->_print($event, $self->phrase('NO_AUTHOR', {author => $author}));
		return;
	}

	my $modules = $cp->modules(authors => [$actual_author]);

	unless ($modules->rv) {
		$self->_print($event, $self->phrase('no', {actual_author => $actual_author}));
		return;
	}

	for my $rpt (keys %{$modules->rv->{$actual_author}})
	{   
		$self->_print($event, $self->phrase('yes', {rpt => "$rpt"}));
	}
}

sub package :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the package of a module') {
	my ($self, $event, $module) = @_;
	my $package = $self->_get_details($event, $module, 'Package');

	return unless $package;

	$self->_print($event, $self->phrase({package => $package}));
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

	my $karma = $self->_get_karma($mail->{_cpan_short});
	my $inform;
	if ($karma) {
		$inform = "$mail->{_cpan_short} $karma by $mail->{_cpan_entered_by}";
	}
	else {
		$inform = "$mail->{_cpan_short} by $mail->{_cpan_entered_by}";
	}
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

	$self->_print($event, $self->phrase({CPAN => '$CPAN', path => $path}));
}

sub readme :Public(privmsg) :Private(notice) :Args(required)
:Help('sends readme for module via DCC CHAT') {
	my ($self, $event, $module) = @_;
	my ($readme, $actual) = $self->_check_module($event, 'readme', $module);
	return unless $readme;

	my $who = $event->{who};

	$self->set("readme_$who", $actual);
	$self->_print($event, $self->phrase({actual => $actual}));
	$self->dcc($who, 'CHAT');
}

sub recent :Private(notice) :Public(privmsg) :Args(refuse)
:Help('shows last ten distributions uploaded to the CPAN') {
	my ($self, $event) = @_;
	my @recent = @{$self->get('recent')};

	if (scalar @recent < 1) {
		$self->_print($event, $self->phrase('just_got_here'));
		return;
	}

	@recent = reverse @recent;
	my $recent = join ', ', @recent;
	$self->_print($event, $self->phrase('results', {results => $recent}));
}

# Unfortunately, until the cpanratings.perl.org people add ratings support
# into the RSS feed we'll have to screen-scrape
sub ratings :Private(notice) :Public(privmsg) :Args(required)
:Help('retrives ratings of a distribution') {
	my ($self, $event, $module) = @_;

	if (!eval{require Socket; Socket::inet_aton('cpanratings.perl.org')}) {
		$self->_print($event, $self->phrase('CPANRATINGS_DOWN'));
		return;
	}

	my $package = $self->_module_to_dist($module);
	my $dist = $self->_extract_name_version($package);
	my $data = $self->_get_cpanratings('ratings', $dist);

	unless ($data->is_success) {
		$self->_print($event, $self->phrase('NO_DISTRIBUTION',
			{module => $module}));
		return;
	}

	my @data = split /\n/, $data->as_string;
	my @ratings;

	for my $rating (@data) {
		if ($rating =~ m!<img src="/images/stars-(\d.\d).png">!) {
			push @ratings, $1;
		}
	}

	if (scalar @ratings == 0) {
		$self->_print($event, $self->phrase('no_ratings', {module => $module}));
		return;
	}

	my $stat = Statistics::Descriptive::Full->new();
	$stat->add_data(@ratings);

	my $mean = sprintf "%.1f", $stat->mean();
	my $median = sprintf "%.1f", $stat->median();
	my $min = sprintf "%.1f", $stat->min();
	my $max = sprintf "%.1f", $stat->max();
	my $stddev = sprintf "%.1f", $stat->standard_deviation();
	my $mode = sprintf "%.1f", $stat->mode();

	my $ratings = scalar @ratings;
	@ratings = reverse @ratings;
	@ratings = splice @ratings, 0, 5;
	my $last5 = join ', ', @ratings;

	$self->_print($event, $self->phrase('ratings',
		{ratings => $last5, n => $ratings, mean => $mean, median => $median,
		min => $min, max => $max, stddev => $stddev, mode => $mode}));
}

sub _ratings_for_reviews {
	my $self = shift;
	my $module = shift;
	my $data = $self->_get_cpanratings('ratings', $module);
	my @data = split /\n/, $data->as_string;
	my @ratings;

	for my $rating (@data) {
		if ($rating =~ m!<img src="/images/stars-(\d.\d).png">!) {
			push @ratings, $1;
		}
	}

	return \@ratings;
}

sub reviews :Private(notice) :Fork :LowPrio :Args(required)
:Help('retrives reviews of a distribution') {
	my ($self, $event, $module) = @_;

	if (!eval{require Socket; Socket::inet_aton('cpanratings.perl.org')}) {
		$self->_print($event, $self->phrase('CPANRATINGS_DOWN'));
		return;
	}

	my $package = $self->_module_to_dist($module);
	my $dist = $self->_extract_name_version($package);
	my $data = $self->_get_cpanratings('reviews', $dist);
	my $items;
	my $p = new XML::RSS::Parser;

	unless (eval {$p->parse($data->content)}) {
		$self->_print($event, $self->phrase('NO_DISTRIBUTION',
			{module => $module}));
		return;
	}

	unless ($items = $p->items) {
		$self->_print($event, $self->phrase('no_reviews', {module => $module}));
		return;
	}

	my @r2r = @{$self->_ratings_for_reviews($dist)};
	my $encode = eval{require Encode; import Encode 'decode_utf8'};
	my $count = 0;

	for my $item (@{$items}) {
		my $creator = $item->{'http://purl.org/dc/elements/1.1/creator'};
		my $description = $item->{'http://purl.org/rss/1.0/description'};

		if ($encode) {
			$creator = decode_utf8($creator);
			$description = decode_utf8($description);
		}

		$self->_print($event, $self->phrase('review', {creator => $creator, description => $description, rating => $r2r[$count]}));
		$count++;
	}
}

sub rt :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the RT www path to a module') {
	my ($self, $event, $module) = @_;
	my ($url, $actual) = $self->_check_module($event, 'module_tree', $module);
	return unless $url;

	my $buffer = 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=';
	my $package = $url->package();

	unless ($package =~ s/\.tgz$|\.tar\.gz$|\.zip$//) {
		$self->_print($event, $self->phrase({actual => $actual}));
		return;
	}

	$buffer .= $package;
	$self->_print($event, $self->phrase('success', {buffer => $buffer}));
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
		$self->_print($event, $self->phrase('too_many_matches',
			{matches => scalar @cache,
			search_max_results => $self->get('search_max_results')}));
	}
	elsif (scalar @cache == 0) {
		$self->_print($event, $self->phrase('no_matches'));
	}
	else {
		for my $key (sort @cache) {
			$self->_print($event, $self->phrase('success', {key => $key}));
		}
	}
}

sub stage :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the stage of a module') {
	my ($self, $event, $module) = @_;
	my $stage = $self->_get_details($event, $module, 'Development Stage');

	return unless $stage;

	$self->_print($event, $self->phrase({stage => $stage}));
}

sub status :Private(notice) :Public(privmsg) :Args(refuse)
:Help('retrieves the status of the bot') {
	my ($self, $event) = @_;
	my $requests = $self->get('requests');

	$self->_print($event, $self->phrase(
		{requests => $requests, s => $requests == 1 ? '' : 's',
		start_time => scalar localtime($^T)}));
}

sub style :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the style of a module') {
	my ($self, $event, $module) = @_;
	my $style = $self->_get_details($event, $module, 'Interface Style');

	return unless $style;

	$self->_print($event, $self->phrase({style => $style}));
}

sub support :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the support level of a module') {
	my ($self, $event, $module) = @_;
	my $support = $self->_get_details($event, $module, 'Support Level');

	return unless $support;

	$self->_print($event, $self->phrase({support => $support}));
}

sub tests :Private(notice) :Fork :LowPrio :Args(required)
:Help('retrieves the test reports of a module') {
	my ($self, $event, $module) = @_;
	my ($report, $actual) = $self->_check_module($event, 'reports', $module);
	return unless $report;

	unless ($report->rv->{$actual}) {
		$self->_print($event, $self->phrase('no_tests', {actual => $actual}));
	}
	else {
		$self->_print($event, $self->phrase('summary',
			{tests => scalar @{$report->rv->{$actual}},
			s => @{$report->rv->{$actual}} == 1 ? '' : 's',
			actual => $actual}));

		for my $rpt (@{$report->rv->{$actual}}) {
			$self->_print($event, $self->phrase('test', {grade => $rpt->{grade}, platform => $rpt->{platform}}));
		}
	}
}

sub url :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the www path to a module') {
	my ($self, $event, $module) = @_;
	my ($url, $actual) = $self->_check_module($event, 'module_tree', $module);
	return unless $url;

	my $author  = $url->author();
	my $package = $url->package();

	unless ($package =~ s/\.tgz$|\.tar\.gz$|\.zip$//) {
		$self->_print($event, $self->phrase('unable_to_get_url',
			{actual => $actual}));
		return;
	}

	my $dist = $self->_extract_name_version($package);

	unless ($dist) {
		$self->_print($event, $self->phrase('not_dist',
			{author => $author, package => $package}));
	}
	else {
		$self->_print($event, $self->phrase('dist', {dist => $dist}));
	}
}

sub version :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the latest version of a module') {
	my ($self, $event, $module) = @_;
	my $version = $self->_get_details($event, $module, 'Version on CPAN');

	return unless $version;

	$self->_print($event, $self->phrase({version => $version}));
}

sub whois :Private(notice) :Public(privmsg) :Args(required)
:Help('gets an author's name and email from a CPAN ID') {
	my ($self, $event, $author) = @_;
	my $cp = $self->get('cp');
	my $actual_author = $self->_check_author($author);

	unless ($actual_author) {
		$self->_print($event, $self->phrase('NO_AUTHOR', {author => $author}));
		return;
	}

	my $cpanauthor = $cp->author_tree->{$actual_author};
	my $name = $cpanauthor->name;
	my $email = $cpanauthor->email || 'no email';

	$self->_print($event, $self->phrase({name => $name, email => $email}));
}

sub wikiurl :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the url of a module's wiki page') {
	my ($self, $event, $module) = @_;
	my ($url, $actual) = $self->_check_module($event, 'module_tree', $module);
	return unless $url;

	$self->_print($event, $self->phrase({module => $module}));
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

				unless ($retval) { $match++ }
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
	my $cp = $self->get('cp');
	$cp->reload_indices(update_source => 1);
	$self->set('last_indice_reload', scalar localtime);
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
