# $Revision: 1.11 $
# $Id: CPAN.pm,v 1.11 2006/07/04 23:27:24 afoxson Exp $
#
# Bot::CPAN - provides CPAN services via IRC
# Copyright (c) 2006 Adam J. Foxson. All rights reserved.
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

require 5.008;

use strict;
use warnings;
use vars qw(@ISA $VERSION);
use base qw(Bot::CPAN::Glue);
use LWP::UserAgent;
use Mail::Internet;
use Math::Round;
use Net::NNTP; 
use POE;
use Statistics::Descriptive;
use URI;
use XML::RSS::Parser;
use Storable;

@ISA = qw(Bot::CPAN::Glue);
($VERSION) = '$Revision: 1.11 $' =~ /\s+(\d+\.\d+)\s+/;

sub dist_existance_check {
    my ($obj, $dist) = @_;
    return if exists $obj->{dists}->{$dist};
    throw Bot::CPAN::E::NoDist($dist);
}

sub auth_existance_check {
    my ($obj, $id) = @_;
    return if exists $obj->{auths}->{$id};
    throw Bot::CPAN::E::NoAuth($id);
}

sub mod_existance_check {
    my ($obj, $mod) = @_;
    return if exists $obj->{mods}->{$mod};
    throw Bot::CPAN::E::NoMod($mod);
}

sub unknown {
    throw Bot::CPAN::E::Unknown();
}

sub status :Private(notice) :Public(privmsg) :Args(refuse)
:Help('retrieves the status of the bot') {
	my ($self, $event) = @_;
	my $requests = $self->get('requests');

	$self->_print($event, $self->phrase(
		{requests => $requests, s => $requests == 1 ? '' : 's',
		start_time => scalar localtime($^T)}));

    return;
}

# Unfortunately, until the cpanratings.perl.org people add ratings support
# into the RSS feed we'll have to screen-scrape
sub dist_ratings :Private(notice) :Public(privmsg) :Args(required)
:Help('retrives ratings of a distribution') {
	my ($self, $event, $module) = @_;

	if (!eval{require Socket; Socket::inet_aton('cpanratings.perl.org')}) {
		$self->_print($event, $self->phrase('CPANRATINGS_DOWN'));
		return;
	}
    my $obj = $self->get('cp');
    dist_existance_check $obj => $module;
    my $dist = $module;
	my $data = $self->_get_cpanratings('ratings', $dist);

	unless ($data->is_success) {
		$self->_print($event, $self->phrase('NO_DISTRIBUTION', {distribution => $module}));
		return;
	}

	my @data = split /\n/, $data->as_string;
	my @ratings;

	for my $rating (@data) {
		if ($rating =~ m!<img src="/images/stars-(\d.\d).png"!) {
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

    return;
}

sub botsnack :Public(privmsg) :Args(refuse)
:Help('gives the bot a snack') {
	my ($self, $event) = @_;
	$self->_print($event, $self->phrase());
    #return;
}

sub config :Private(notice) :Args(refuse) :Admin :LowPrio
:Help('Shows the bot\'s configuration') {
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
	$self->_print($event, $self->phrase('inform_channel_of_new_ratings',
		{inform_channel_of_new_ratings =>
			$self->get('inform_channel_of_new_ratings')}));
	$self->_print($event, $self->phrase('name',
		{name => $self->name}));
	$self->_print($event, $self->phrase('news_server',
		{news_server => $self->get('news_server')}));
	$self->_print($event, $self->phrase('nickserv_password',
		{nickserv_password => $self->get('nickserv_password')}));
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

    return;
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

    return;
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

    return;
}

sub _add_to_recent {
	my ($self, $dist) = @_;
	my @recent = @{$self->get('recent')};

	shift @recent if scalar @recent == 10;
	push @recent, $dist;

	$self->set('recent', \@recent);
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

# this is called the moment we successfully connect to a server
sub connected {
	my $self = shift;

    if ($self->get('nickserv_password')) {
        $poe_kernel->post($self->{IRCNAME}, 'privmsg', 'nickserv', "IDENTIFY ${\($self->get('nickserv_password'))}");
    }

    my $cp = retrieve('/home/afoxson/.cpanbot/index') unless $self->get('cp');

	$self->set('cp', $cp) unless $self->get('cp');
	$self->set('requests', 0) unless $self->get('requests');
	$self->set('recent', []) unless $self->get('recent') and ref $self->get('recent') eq 'ARRAY';

	my $nntp = Net::NNTP->new($self->get('news_server')) or
		die "Cannot open NNTP server: $!";
	my ($articles) = ($nntp->group($self->get('group')))[0] or
		die "Cannot go to group: $!";
	$self->set('articles', $articles + 1);
	$self->set('ratings', undef);

	$poe_kernel->state('_reload_indices', $self);
	$poe_kernel->state('_inform_channel_of_new_uploads', $self);
	$poe_kernel->state('_inform_channel_of_new_ratings', $self);
	$poe_kernel->delay('reconnect');
	$poe_kernel->delay_add('_reload_indices', 0);
	$poe_kernel->delay_add('_inform_channel_of_new_uploads',
		$self->get('inform_channel_of_new_uploads'));
	$poe_kernel->delay_add('_inform_channel_of_new_ratings',
		$self->get('inform_channel_of_new_ratings'));
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

	if ($type eq 'ratings') {
		$place = "http://cpanratings.perl.org/dist/$module";
	}

	my $url = URI->new($place);
	my $req = HTTP::Request->new(GET => $url);
	my $data = $ua->request($req);

	return $data;
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
				if ($rating =~ m!<img src="/images/stars-(\d.\d).png"!) {
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

sub _parse_article {
	my ($self, $mail) = @_;
	my $body = join '', @{$mail->body()};

	unless ($body =~
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
		^ Request\ entered\ by: \s ([A-Z]{3,9}) \s \( .* \) \s* $ \n
		^ Request\ entered\ on: \s (.+) \s* $ \n
		^ Request\ completed: \s (.+) \s* $ \n
		^ $ \n
		^ .+ $ \n
		^ .+ $
	/mx) {
        return 1;
    }

	$mail->{_cpan_file}       = $2;
	$mail->{_cpan_entered_by} = $5;

	unless ($mail->{_cpan_file} =~ /\.tgz$|\.tar\.gz$|\.zip$/) {
        return 2;
    }

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

sub _inform_channel_of_new_ratings {
	my $self = $_[OBJECT];
    my $p = XML::RSS::Parser->new();
    my $feed = $p->parse_uri('http://cpanratings.perl.org/index.rss');
    my $report = 1;

    $self->log("Starting rating ID=${\($self->get('ratings') ? $self->get('ratings') : 'undef')}\n");

    $report = 0 unless $self->get('ratings');

    # output some values
    for my $review ( reverse $feed->query('//item') ) {
        my $title = $review->query('title')->text_content;
        my $link = $review->query('link')->text_content;
        my $description = $review->query('description')->text_content;
        my $creator = $review->query('dc:creator')->text_content;
        my ($id) = $link =~ m!.+\#(\d+)!;

        if ($self->get('ratings')) {
            next if $id <= $self->get('ratings');
        }

        next unless $description =~ /\n/;

        my ($rating) = (split /\n/, $description)[0];
        $rating =~ s/Rating:\s//;
        $rating =~ s/1\sstars/1 star/;

        next unless $rating =~ /stars?/;

        $self->set('ratings', $id);
        my $inform = "$title rated $rating by $creator";
    	my $chan_inform = "rating: $inform";

        if ($report) {
	        for my $channel ($self->channels()) {
                $self->emote({channel => $channel, body => $chan_inform}) if
                    $self->_check_policy($channel, $inform);
            }
        }
    }

    $self->log("Ending rating ID=${\($self->get('ratings'))}\n");

	$poe_kernel->delay_add('_inform_channel_of_new_ratings',
		$self->get('inform_channel_of_new_ratings'));
}

sub _reload_indices {
	my $self = $_[OBJECT];
    $self->log("Getting indices...\n");
	$self->set('cp', undef);
    my $cp = retrieve('/home/afoxson/.cpanbot/index');
	$self->set('cp', $cp);
	$self->set('last_indice_reload', scalar localtime);
	$poe_kernel->delay_add('_reload_indices',
		$self->get('reload_indices_interval'));
}

sub irc_disconnected_state { 
	my ($this, $server) = @_[OBJECT, ARG0];
	$this->log("Lost connection to server $server.\n");
	$poe_kernel->delay('_reload_indices' => undef);
	$poe_kernel->delay('_inform_channel_of_new_uploads' => undef);
	$poe_kernel->delay('_inform_channel_of_new_ratings' => undef);
	$poe_kernel->delay('reconnect' => 60);
}

sub irc_error_state { 
	my ($this, $err) = @_[OBJECT, ARG0];
	$this->log("Server error occurred! $err\n");
	$poe_kernel->delay('_reload_indices' => undef);
	$poe_kernel->delay('_inform_channel_of_new_uploads' => undef);
	$poe_kernel->delay('_inform_channel_of_new_ratings' => undef);
	$poe_kernel->delay('reconnect' => 60);
}

sub irc_socketerr_state {
	my ($this, $err) = @_[OBJECT, ARG0];
	$this->log("Socket error occurred: $err\n");
	$poe_kernel->delay('_reload_indices' => undef);
	$poe_kernel->delay('_inform_channel_of_new_uploads' => undef);
	$poe_kernel->delay('_inform_channel_of_new_ratings' => undef);
	$poe_kernel->delay('reconnect' => 60);
}

# Just.. don't.. ask..
sub proxy :Private(notice) :Args(required) :Admin
:Help('proxies an emote') {
	my ($self, $event, $spec) = @_;
    my ($channel, $emote) = split /\|/, $spec;
    $emote =~ s/_/ /g;
    $self->emote({channel => $channel, body => $emote});
}

sub modlist_catid2desc {
	my $id = shift;

	if ($id == 2) { return "($id) Perl Core Modules, Perl Language Extensions and Documentation Tools" }
	elsif ($id == 3) { return "($id) Development Support" }
	elsif ($id == 4) { return "($id) Operating System Interfaces, Hardware Drivers" }
	elsif ($id == 5) { return "($id) Networking, Device Control (modems) and InterProcess Communication" }
	elsif ($id == 6) { return "($id) Data Types and Data Type Utilities" }
	elsif ($id == 7) { return "($id) Database Interfaces" }
	elsif ($id == 8) { return "($id) User Interfaces (Character and Graphical)" }
	elsif ($id == 9) { return "($id) Interfaces to or Emulations of Other Programming Languages" }
	elsif ($id == 10) { return "($id) File Names, File Systems and File Locking" }
	elsif ($id == 11) { return "($id) String Processing, Language Text Processing, Parsing and Searching" }
	elsif ($id == 12) { return "($id) Option, Argument, Parameter and Configuration File Processing" }
	elsif ($id == 13) { return "($id) Internationalization and Locale" }
	elsif ($id == 14) { return "($id) Authentication, Security and Encryption" }
	elsif ($id == 15) { return "($id) World Wide Web, HTML, HTTP, CGI, MIME etc" }
	elsif ($id == 16) { return "($id) Server and Daemon Utilities" }
	elsif ($id == 17) { return "($id) Archiving, Compression and Conversion" }
	elsif ($id == 18) { return "($id) Images, Pixmap and Bitmap Manipulation, Drawing and Graphing" }
	elsif ($id == 19) { return "($id) Mail and Usenet News" }
	elsif ($id == 20) { return "($id) Control Flow Utilities (callbacks and exceptions etc)" }
	elsif ($id == 21) { return "($id) File Handle, Directory Handle and Input/Output Stream Utilities" }
	elsif ($id == 22) { return "($id) Microsoft Windows Modules" }
	elsif ($id == 23) { return "($id) Miscellaneous Modules" }
	elsif ($id == 24) { return "($id) Interface Modules to Commercial Software" }
	elsif ($id == 25) { return "($id) Bundles" }
	else { return "($id) Unknown" }
}

sub id_dists :Private(notice) :Args(required) :Fork :LowPrio
:Help('shows all distributions of an author') {
	my ($self, $event, $id) = @_;
    my $obj = $self->get('cp');
    auth_existance_check $obj => $id;

	my %ids;
	for my $dist (keys %{$obj->{dists}}) {
		push @{$ids{$obj->{dists}->{$dist}->{cpanid}}}, $dist;
	}

    if (exists $ids{$id}) {
        while (my @dists = splice @{$ids{$id}}, 0, 15) {
            $self->_print($event, $self->phrase({id_dists => join ', ', @dists}));
        }
    }
    else {
        $self->_print($event, $self->phrase({id_dists => 'None!?'}));
    }
}

sub dist_tests :Private(notice) :Public(privmsg) :Args(required)
:Help('shows tests results for a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');
    dist_existance_check $obj => $dist;
	if (not defined $obj->{dists}->{$dist}->{cpanid}) {
		$self->_print($event, $self->phrase('UNKNOWN'));
        return;
    }
	if (!eval{require Socket; Socket::inet_aton('search.cpan.org')}) {
		$self->_print($event, $self->phrase('SEARCH_CPAN_ORG_DOWN'));
		return;
	}
	my $id = $obj->{dists}->{$dist}->{cpanid};
    my $ua = LWP::UserAgent->new(agent => "Bot::CPAN/$VERSION");
    my $place = "http://search.cpan.org/~$id/$dist/";
    my $url = URI->new($place);
    my $req = HTTP::Request->new(GET => $url);
    my $data = $ua->request($req);

    if ($data->is_success) {
        my @buffer;
        my ($pass) = $data->as_string =~ m/PASS\s\((\d+)\)/;
        my ($fail) = $data->as_string =~ m/FAIL\s\((\d+)\)/;
        my ($na) = $data->as_string =~ m/NA\s\((\d+)\)/;
        my ($unknown) = $data->as_string =~ m/UNKNOWN\s\((\d+)\)/;

        push @buffer, "PASS ($pass)" if defined $pass;
        push @buffer, "FAIL ($fail)" if defined $fail;
        push @buffer, "NA ($na)" if defined $na;
        push @buffer, "UNKNOWN ($unknown)" if defined $unknown;

        if (scalar @buffer > 0) {
	        $self->_print($event, $self->phrase({tests => join ' ', @buffer}));
            return;
        }
        else {
		    $self->_print($event, $self->phrase('NO_TESTS_FOR_DIST', {distribution => $dist}));
            return;
        }
    }
    else {
		$self->_print($event, $self->phrase('SEARCH_CPAN_ORG_DOWN'));
        return;
    }
}

sub mod_stage :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the stage of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
	unknown unless defined $obj->{mods}->{$mod}->{dslip};
	my $character = substr $obj->{mods}->{$mod}->{dslip}, 0, 1;
	unknown unless defined $character and $character;
	if ($character eq 'i') { $self->_print($event, $self->phrase({stage => 'Idea'})) }
	elsif ($character eq 'c') { $self->_print($event, $self->phrase({stage => 'Under construction'})) }
    elsif ($character eq 'a') { $self->_print($event, $self->phrase({stage => 'Alpha'})) }
    elsif ($character eq 'b') { $self->_print($event, $self->phrase({stage => 'Beta'})) }
    elsif ($character eq 'R') { $self->_print($event, $self->phrase({stage => 'Released'})) }
    elsif ($character eq 'M') { $self->_print($event, $self->phrase({stage => 'Mature'})) }
    elsif ($character eq 'S') { $self->_print($event, $self->phrase({stage => 'Standard'})) }
	else { unknown }
}

sub mod_support :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the support level of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
	unknown unless defined $obj->{mods}->{$mod}->{dslip};
	my $character = substr $obj->{mods}->{$mod}->{dslip}, 1, 1;
	unknown unless defined $character and $character;
    if ($character eq 'm') { $self->_print($event, $self->phrase({support => 'Mailing-list'})) }
    elsif ($character eq 'd') { $self->_print($event, $self->phrase({support => 'Developer'})) }
    elsif ($character eq 'u') { $self->_print($event, $self->phrase({support => 'Usenet newsgroup'})) }
    elsif ($character eq 'n') { $self->_print($event, $self->phrase({support => 'None known'})) }
	else { unknown }
}

sub mod_language :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the language of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
	unknown unless defined $obj->{mods}->{$mod}->{dslip};
	my $character = substr $obj->{mods}->{$mod}->{dslip}, 2, 1;
	unknown unless defined $character and $character;
    if ($character eq 'p') { $self->_print($event, $self->phrase({language => 'Perl-only'})) }
    elsif ($character eq 'c') { $self->_print($event, $self->phrase({language => 'C and perl'})) }
    elsif ($character eq 'h') { $self->_print($event, $self->phrase({language => 'Hybrid'})) }
    elsif ($character eq '+') { $self->_print($event, $self->phrase({language => 'C++ and perl'})) }
    elsif ($character eq 'o') { $self->_print($event, $self->phrase({language => 'perl and another language other than C or C++'})) }
	else { unknown }
}

sub mod_style :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the style of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
	unknown unless defined $obj->{mods}->{$mod}->{dslip};
	my $character = substr $obj->{mods}->{$mod}->{dslip}, 3, 1;
	unknown unless defined $character and $character;
    if ($character eq 'f') { $self->_print($event, $self->phrase({style => 'Plain Functions'})) }
    elsif ($character eq 'h') { $self->_print($event, $self->phrase({style => 'Hybrid, object and function interfaces available'})) }
    elsif ($character eq 'n') { $self->_print($event, $self->phrase({style => 'No interface'})) }
    elsif ($character eq 'r') { $self->_print($event, $self->phrase({style => 'Some use of unblessed References or ties'})) }
    elsif ($character eq 'O') { $self->_print($event, $self->phrase({style => 'Object oriented using blessed references and/or inheritance'})) }
	else { unknown }
}

sub mod_license :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the license of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
	unknown unless defined $obj->{mods}->{$mod}->{dslip};
	my $character = substr $obj->{mods}->{$mod}->{dslip}, 4, 1;
	unknown unless defined $character and $character;
    if ($character eq 'p') { $self->_print($event, $self->phrase({license => 'Standard-Perl'})) }
    elsif ($character eq 'g') { $self->_print($event, $self->phrase({license => 'GPL'})) }
    elsif ($character eq 'l') { $self->_print($event, $self->phrase({license => 'LGPL'})) }
    elsif ($character eq 'b') { $self->_print($event, $self->phrase({license => 'BSD'})) }
    elsif ($character eq 'a') { $self->_print($event, $self->phrase({license => 'Artistic license'})) }
    elsif ($character eq 'o') { $self->_print($event, $self->phrase({license => 'other'})) }
	else { unknown }
}

sub top10 :Private(notice) :Public(privmsg) :Args(refuse)
:Help('top 10 contributors to CPAN') {
	my ($self, $event) = @_;
    my $obj = $self->get('cp');
	my %ids;
	for my $dist (keys %{$obj->{dists}}) {
		$ids{$obj->{dists}->{$dist}->{cpanid}}++;
	}

	my $count = 0;
	my @top10;
	for my $id (sort {$ids{$b} <=> $ids{$a}} keys %ids) {
		last if $count > 9;
		push @top10, "$id ($ids{$id})";
		$count++;
	}

    $self->_print($event, $self->phrase({top10 => join ', ', @top10}));
}

sub id_name :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves a name from a PAUSE ID') {
	my ($self, $event, $id) = @_;
    my $obj = $self->get('cp');
    $id = uc($id);
    auth_existance_check $obj => $id;
    unknown unless defined $obj->{auths}->{$id}->{fullname};
    $self->_print($event, $self->phrase({name => $obj->{auths}->{$id}->{fullname}}));
}

sub id_email :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves an email from a PAUSE ID') {
	my ($self, $event, $id) = @_;
    my $obj = $self->get('cp');
    $id = uc($id);
    auth_existance_check $obj => $id;
    unknown unless defined $obj->{auths}->{$id}->{email};
    $self->_print($event, $self->phrase({email => $obj->{auths}->{$id}->{email}}));
}

sub mod_version :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the version of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
    unknown unless defined $obj->{mods}->{$mod}->{version};
    $self->_print($event, $self->phrase({mod_version => $obj->{mods}->{$mod}->{version}}));
}

sub mod_rturl :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the RT URL of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
    $self->_print($event, $self->phrase({mod_rturl => "http://rt.cpan.org/Public/Dist/Display.html?Name=$mod"}));
}

sub mod_docurl :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the documentation URL of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
    $self->_print($event, $self->phrase({mod_docurl => "http://search.cpan.org/perldoc?$mod"}));
}

sub mod_dist :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the distribution of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
    unknown unless defined $obj->{mods}->{$mod}->{dist};
    $self->_print($event, $self->phrase({mod_dist => $obj->{mods}->{$mod}->{dist}}));
}

sub mod_id :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the PAUSE ID of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
    unknown unless defined $obj->{mods}->{$mod}->{dist};
    unknown unless defined $obj->{dists}->{$obj->{mods}->{$mod}->{dist}}->{cpanid};
    $self->_print($event, $self->phrase({mod_id => $obj->{dists}->{$obj->{mods}->{$mod}->{dist}}->{cpanid}}));
}

sub mod_desc :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the description of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
    unknown unless defined $obj->{mods}->{$mod}->{description};
    $self->_print($event, $self->phrase({mod_desc => $obj->{mods}->{$mod}->{description}}));
}

sub mod_chapter :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the chapter of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
    unknown unless defined $obj->{mods}->{$mod}->{chapterid};
    $self->_print($event, $self->phrase({mod_chapter => modlist_catid2desc($obj->{mods}->{$mod}->{chapterid})}));
}

sub mod_dslip :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the DSLIP of a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');
    mod_existance_check $obj => $mod;
    unknown unless defined $obj->{mods}->{$mod}->{dslip};
    $self->_print($event, $self->phrase({mod_dslip => $obj->{mods}->{$mod}->{dslip}}));
}

sub mod_search :Private(notice) :Args(required) :Fork :LowPrio
:Help('search for a module') {
	my ($self, $event, $mod) = @_;
    my $obj = $self->get('cp');

    if ($mod !~ /^[A-Za-z0-9]+$/) {
        $self->_print($event, $self->phrase('BAD_SEARCH_TERMS'));
	    return;
    }

	my @found;
	for my $module (keys %{$obj->{mods}}) {
		push @found, $module if $module =~ /$mod/;
	}

    if (scalar @found > 0) {
        while (my @results = splice @found, 0, 15) {
            $self->_print($event, $self->phrase({mod_search => join ', ', @results}));
        }
    }
    else {
        $self->_print($event, $self->phrase('NO_RESULTS'));
    }
}

sub dist_version :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the version of a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');
    dist_existance_check $obj => $dist;
    unknown unless defined $obj->{dists}->{$dist}->{version};
    $self->_print($event, $self->phrase({dist_version => $obj->{dists}->{$dist}->{version}}));
}

sub dist_dlurl :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the download URL of a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');
    dist_existance_check $obj => $dist;
	unknown unless defined $obj->{dists}->{$dist}->{filename};
	unknown unless defined $obj->{dists}->{$dist}->{cpanid};
	my $filename = $obj->{dists}->{$dist}->{filename};
	my $id = $obj->{dists}->{$dist}->{cpanid};
	my $url = 'http://search.cpan.org/CPAN/authors/id/';
	my $dir = substr $id, 0, 1;
	my $sub_dir = substr $id, 0, 2;
    $self->_print($event, $self->phrase({dist_dlurl => $url . "$dir/" . "$sub_dir/" . "$id/" . $filename}));
}

sub dist_path :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the path to a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');
    dist_existance_check $obj => $dist;
	unknown unless defined $obj->{dists}->{$dist}->{filename};
	unknown unless defined $obj->{dists}->{$dist}->{cpanid};
	my $filename = $obj->{dists}->{$dist}->{filename};
	my $id = $obj->{dists}->{$dist}->{cpanid};
	my $dir = substr $id, 0, 1;
	my $sub_dir = substr $id, 0, 2;
    $self->_print($event, $self->phrase({dist_path => "\$CPAN/authors/id/" . "$dir/" . "$sub_dir/" . "$id/" . $filename}));
}

sub dist_filename :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the filename of a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');
    dist_existance_check $obj => $dist;
    unknown unless defined $obj->{dists}->{$dist}->{filename};
    $self->_print($event, $self->phrase({dist_filename => $obj->{dists}->{$dist}->{filename}}));
}

sub dist_id :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves PAUSE ID of a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');
    dist_existance_check $obj => $dist;
    unknown unless defined $obj->{dists}->{$dist}->{cpanid};
    $self->_print($event, $self->phrase({dist_id => $obj->{dists}->{$dist}->{cpanid}}));
}

sub dist_desc :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves description of a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');
    dist_existance_check $obj => $dist;
    unknown unless defined $obj->{dists}->{$dist}->{description};
    $self->_print($event, $self->phrase({dist_desc => $obj->{dists}->{$dist}->{description}}));
}

sub dist_url :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves URL of a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');
    dist_existance_check $obj => $dist;
    $self->_print($event, $self->phrase({dist_url => "http://search.cpan.org/dist/$dist/"}));
}

sub dist_size :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the size of a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');
    dist_existance_check $obj => $dist;
    unknown unless defined $obj->{dists}->{$dist}->{size};
    $self->_print($event, $self->phrase({dist_size => $obj->{dists}->{$dist}->{size}}));
}

sub dist_date :Private(notice) :Public(privmsg) :Args(required)
:Help('retrieves the release date of a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');
    dist_existance_check $obj => $dist;
    unknown unless defined $obj->{dists}->{$dist}->{date};
    $self->_print($event, $self->phrase({dist_date => $obj->{dists}->{$dist}->{date}}));
}

sub dist_search :Private(notice) :Args(required) :Fork :LowPrio
:Help('search for a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');

    if ($dist !~ /^[A-Za-z0-9]+$/) {
        $self->_print($event, $self->phrase('BAD_SEARCH_TERMS'));
	    return;
    }

	my @found;
	for my $distribution (keys %{$obj->{dists}}) {
		push @found, $distribution if $distribution =~ /$dist/;
	}

    if (scalar @found > 0) {
        while (my @results = splice @found, 0, 15) {
            $self->_print($event, $self->phrase({dist_search => join ', ', @results}));
        }
    }
    else {
        $self->_print($event, $self->phrase('NO_RESULTS'));
    }
}

sub dist_mods :Private(notice) :Args(required) :Fork :LowPrio
:Help('lists all modules in a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');
    dist_existance_check $obj => $dist;
	if (not exists $obj->{dists}->{$dist}->{modules}) {
        $self->_print($event, $self->phrase('NO_MODULES_IN_DISTRIBUTION', {dist => $dist}));
        return;
    }
	if (not ref $obj->{dists}->{$dist}->{modules} eq 'HASH') {
        $self->_print($event, $self->phrase('NO_MODULES_IN_DISTRIBUTION', {dist => $dist}));
        return;
    }
	if (not scalar keys %{$obj->{dists}->{$dist}->{modules}} > 0) {
        $self->_print($event, $self->phrase('NO_MODULES_IN_DISTRIBUTION', {dist => $dist}));
        return;
    }
	my @mods;
    for my $module (keys %{$obj->{dists}->{$dist}->{modules}}) {
		push @mods, $module;
    }

    if (scalar @mods > 0) {
        while (my @results = splice @mods, 0, 15) {
            $self->_print($event, $self->phrase({dist_mods => join ', ', @results}));
        }
    }
    else {
        $self->_print($event, $self->phrase('NO_RESULTS'));
    }
}

sub dist_chapter :Private(notice) :Public(privmsg) :Args(required)
:Help('lists the chapter of a distribution') {
	my ($self, $event, $dist) = @_;
    my $obj = $self->get('cp');
    dist_existance_check $obj => $dist;
	if (not exists $obj->{dists}->{$dist}->{chapterid}) {
        $self->_print($event, $self->phrase('NO_CHAPTER_FOR_DISTRIBUTION', {dist => $dist}));
        return;
    }
	if (not ref $obj->{dists}->{$dist}->{chapterid} eq 'HASH') {
        $self->_print($event, $self->phrase('NO_CHAPTER_FOR_DISTRIBUTION', {dist => $dist}));
        return;
    }
	if (not scalar keys %{$obj->{dists}->{$dist}->{chapterid}} > 0) {
        $self->_print($event, $self->phrase('NO_CHAPTER_FOR_DISTRIBUTION', {dist => $dist}));
        return;
    }
	my %chapters_pre;
    for my $id (keys %{$obj->{dists}->{$dist}->{chapterid}}) {
		for my $sc (keys %{$obj->{dists}->{$dist}->{chapterid}->{$id}}) {
			push @{$chapters_pre{modlist_catid2desc($id)}}, $sc; 
		}
	}

	my @chapters_post;

	for my $key (sort {$a cmp $b} keys %chapters_pre) {
		my $subs = join ', ', @{$chapters_pre{$key}};
		push @chapters_post, "$key > $subs";
	}

    $self->_print($event, $self->phrase({dist_chapter => join '; ', @chapters_post}));
}

1;
