# $Revision: 1.17 $
# $Id: Glue.pm,v 1.17 2003/03/17 05:48:10 afoxson Exp $

# Bot::CPAN::Glue - Deep magic for Bot::CPAN
# Copyright (c) 2003 Adam J. Foxson. All rights reserved.

# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Bot::CPAN::Glue;

require 5.006;

use strict;
use Digest::MD5;
use POE;
use vars qw(@ISA @EXPORT $VERSION %commands);
use Bot::CPAN::BasicBot;
use constant NOT_A_COMMAND   => 0;
use constant PUBLIC_COMMAND  => 1<<0;
use constant PRIVATE_COMMAND => 1<<1;
use constant FORK            => 1<<2;
use constant LOW_PRIO        => 1<<3;
use constant PUBLIC_NOTICE   => 1<<4;
use constant PUBLIC_PRIVMSG  => 1<<5;
use constant PRIVATE_NOTICE  => 1<<6;
use constant PRIVATE_PRIVMSG => 1<<7;
use constant PERM            => 0;
use constant HELP            => 1;
use constant ARG             => 2;
use Attribute::Handlers autotie => {
	'__CALLER__::Public'  => __PACKAGE__,
	'__CALLER__::Private' => __PACKAGE__,
	'__CALLER__::Fork'    => __PACKAGE__,
	'__CALLER__::LowPrio' => __PACKAGE__,
	'__CALLER__::Help'    => __PACKAGE__,
	'__CALLER__::Args'    => __PACKAGE__,
};

($VERSION) = '$Revision: 1.17 $' =~ /\s+(\d+\.\d+)\s+/;
@ISA       = qw(Bot::CPAN::BasicBot);

local $^W;

# this is the command handler, here we are ultimately responsible for
# accepting or rejecting a command
sub _command {
	my ($self, $message) = @_;

	return unless
		my ($command, $module_or_author) = $self->_parse_command($message);
	return unless
		$self->_verify_usage($message, $command, $module_or_author);

	$self->set('requests', $self->get('requests') + 1);
	$message->{data} = $command;
	$self->log("DEBUG: _command: $command, $module_or_author\n") if
		$self->debug;
	$self->_dispatch($message, $module_or_author);
}

sub _commands {
	return keys %commands;
}

# here we determine how to dispatch a given command, and then dispatch it for
# execution. this serves to adapt the incompatible api's of B::B and POE
sub _dispatch {
	my ($self, $message, $module_or_author) = @_;
	my $command = $message->{data};

	if (defined $commands{$command}[PERM] and
		$commands{$command}[PERM] & FORK) {
			$self->log("DEBUG: _dispatch: fork $command, $module_or_author\n") if $self->debug;
			$self->forkit({
				run => \&{"${\(ref($self))}::$command"},
				handler => '_fork_handler',
				body => $self,
				who => $message->{who},
				channel => $message->{channel},
				arguments => [$message, $module_or_author],
				data => $message->{data},
		});
	} 
	else {
		$self->log("DEBUG: _dispatch: non-fork $command, $module_or_author\n") if $self->debug;
		$self->$command($message, $module_or_author);
	}
}

# this gets indirectly called by _print from within any forked command to
# prepare data to be sent back to the user
sub _fork_handler {
	my ($self, $body, $wheel_id) = @_[0, ARG0, ARG1];
	chomp $body;

	# this is not particularly endearing, but it has to be done *sigh*
	# why? if we don't do this here than the requesting user will also be
	# sent internal CPANPLUS debugging info. this ensures that the user gets
	# sent only what they ask for
	my $passthrough_pattern = __PACKAGE__;
	unless ($body =~ /^$passthrough_pattern:\s/) {
		$self->log("$body\n");
		return;
	}
	$body =~ s/$passthrough_pattern: //;

	my $args = $self->{forks}->{$wheel_id}->{args};

	$self->log("DEBUG: _fork_handler: " . $args->{data} . "\n") if $self->debug;

	$args->{body} = $body;
	$self->_return($args);
}

# we return the method by which data should be returned, either via a notice
# or a privmsg. we also determine if the data should be sent back with normal
# or low priority
sub _get_type {
	my ($self, $message) = @_;
	my $command = $message->{data};
	my $type;

	if ($message->{channel} eq "msg") {
		$type = 'notice'; # the default
		$type = 'privmsg' if $command and
			defined $commands{$command}[PERM] and
			$commands{$command}[PERM] & PRIVATE_PRIVMSG;
	}
	else {
		$type = 'privmsg'; # the default
		$type = 'notice' if $command and
			defined $commands{$command}[PERM] and
			$commands{$command}[PERM] & PUBLIC_NOTICE;
	}

	$type .= 'low' if $command and defined $commands{$command}[PERM] and
		$commands{$command}[PERM] & LOW_PRIO;

	$self->log("DEBUG: _get_type" . (defined $command ? ": $command" : '') . (defined $type ? ": $type" : '') . "\n") if $self->debug;

	return $type;
}

sub _help {
	my $command = $_[1];

	if (not exists $commands{$command}) {
		return "No such command: $command\n";
	}
	elsif (not defined $commands{$command}[HELP]) {
		return "No help is available for: $command\n";
	}
	else {
		return $commands{$command}[HELP];
	}
}

# ordinarily, we wouldn't need to define our own constructor, but since we
# need to add our own options (news_server, group, etc) to the options that
# Bot::CPAN::Basicbot provides we'll need to separate the options that B::C::B
# expects from the options that B::C expects
sub new {
	my $self = shift;
	my (@upstream_args, @my_args);

	while (my ($key, $value) = splice @_, 0, 2) {
		if ($key eq 'news_server' ||
			$key eq 'group' ||
			$key eq 'reload_indices_interval' ||
			$key eq 'policy' ||
			$key eq 'search_max_results' ||
			$key eq 'inform_channel_of_new_uploads') {
				push @my_args, $key, $value;
		}
		else {
			push @upstream_args, $key, $value;
		}
	}

	my $upstream = $self->SUPER::new(@upstream_args);

	# set up some sane defaults
	$upstream->set('news_server', 'nntp.perl.org');
	$upstream->set('search_max_results', 20);
	$upstream->set('group', 'perl.cpan.testers');
	$upstream->set('reload_indices_interval', 300);
	$upstream->set('inform_channel_of_new_uploads', 60);
	$upstream->set('policy', {});

	while (my ($key, $value) = splice @my_args, 0, 2) {
		$upstream->set($key, $value);
	}

	$upstream->_verify_policy();

	return $upstream;
}

# make sure that we are given a valid command, and that it's well formed
sub _parse_command {
	my ($self, $message) = @_;
	my $cmds = join '|', keys %commands;
	my $body = $message->{body};

	unless ($body =~ m/
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
	/imx) {
		my @invalid = ('huh?', 'hm?', 'excuse me?', 'pardon me?');
		my $invalid = $invalid[int(rand(scalar @invalid))];
		$message->{body} = $invalid;
		$self->_return($message);
		return;
	}

	my ($command, $module_or_author) = ($1, $2);

	$command = lc $command;
	$module_or_author = '' unless defined $module_or_author;

	return ($command, $module_or_author);
}

# here we determine how specifically to return data to the user
sub _print {
	my ($self, $message, $payload) = @_;

	if (defined $commands{$message->{data}}[PERM] and
		$commands{$message->{data}}[PERM] & FORK) {
			print __PACKAGE__ . ": " . $payload . "\n";
	}
	else {
		$message->{body} = $payload;
		$self->_return($message);
	}
}

sub _private_command {
	my $command = $_[1];
	return unless defined $commands{$command}[PERM];
	return $commands{$command}[PERM] & PRIVATE_COMMAND;
}

sub _public_command {
	my $command = $_[1];
	return unless defined $commands{$command}[PERM];
	return $commands{$command}[PERM] & PUBLIC_COMMAND;
}

# returns data directly to the requesting user
sub _return
{
	my ($self, $message) = @_;
	my $body = $message->{body} || '';

	my $who = ($message->{channel} eq "msg") ?
		$message->{who} : $message->{channel};

	unless ($who && $body) {
		$self->log("target and body are required ($who/$body)\n");
		return;
	}

	$body = "$message->{who}: $body" if
		$message->{channel} ne "msg" and $message->{address};

	my $type = $self->_get_type($message);

	$self->log("DEBUG: _return" . (defined $who ? ": $who" : '') . (defined $message->{data} ? ": $message->{data}" : '') . "\n") if
		$self->debug;

	$self->$type($who, $body);
}

# this is the entrance for all incoming communication events
sub said {
	my ($self, $message) = @_;

	# say nothing if we are not specifically addressed
	return undef unless $message->{address}; 

	$self->_command($message);
}

sub _verify_policy {
	my $self = shift;
	my $policy = $self->get('policy');

	# we are guaranteed that the policy "exists", internally speaking..
	# so.. if it's not defined don't bother verifying it..
	return unless defined $policy;

	# since it is defined, let's make sure it's a hashref
	die "Policy must be a hashref\n" unless ref $policy eq 'HASH';

	# empty policy? don't bother verifying..
	return unless scalar keys %{$policy} > 0;

	# ok, we have a policy, lets check it
	my $channels = join '|', $self->channels;
	for my $channel (sort keys %{$policy}) {
		# make sure that all channels in 'policy' are listed in 'channels'
		die "$channel is not specified in 'channels'\n" unless
			$channel =~ /^$channels$/;

		my $chanpol = $policy->{$channel};

		# if there is an undefined channel policy, skip it!
		next unless defined $chanpol;

		# however, if it is defined and not a hashref, that's a no-no
		die "Policy for $channel must be a hashref\n" unless
			ref $chanpol eq 'HASH';

		# and skip it if it's empty
		next unless scalar keys %{$chanpol} > 0;

		# make sure they didn't, say, mis-spell something
		for my $key (sort keys %{$chanpol}) {
			die "Channel policy for $channel specifies unknown type of: $key\nValid types are: allow, deny.\n" if $key !~ /^allow|deny$/;
		}

		# if they do specify an allow/deny, make sure they are defined
		die "Allow policy for $channel must be defined\n" if
			exists $chanpol->{allow} and not defined $chanpol->{allow};
		die "Deny policy for $channel must be defined\n" if
			exists $chanpol->{deny} and not defined $chanpol->{deny};
	}
}

# make sure the user is using a given command in an appropriate manner
sub _verify_usage {
	my ($self, $message, $command, $module_or_author) = @_;
	my $type = $message->{channel} eq 'msg' ? PRIVATE_COMMAND : PUBLIC_COMMAND;

	if (defined $commands{$command}[PERM]) {
		unless ($type & $commands{$command}[PERM]) {
			if ($commands{$command}[PERM] & PUBLIC_COMMAND) {
				$message->{body} = "'$command' is a public only command";
				$self->_return($message);
				return;
			}
			elsif ($commands{$command}[PERM] & PRIVATE_COMMAND) {
				$message->{body} = "'$command' is a private only command";
				$self->_return($message);
				return;
			}
		}
	}

	if (defined $commands{$command}[ARG]) { 
		if ($commands{$command}[ARG] eq 'required' && not $module_or_author) {
			$message->{body} = "'$command' requires an argument";
			$self->_return($message);
			return;
		}
		elsif ($commands{$command}[ARG] eq 'refuse' && $module_or_author) {
			$message->{body} = "'$command' accepts no argument";
			$self->_return($message);
			return;
		}
	}

	return 1;
}

# and here are the attribute handlers

sub Fork : ATTR(CODE)    { $commands{*{$_[1]}{NAME}}[PERM] |= FORK }
sub Help : ATTR(CODE)    { $commands{*{$_[1]}{NAME}}[HELP] = $_[4] }
sub LowPrio : ATTR(CODE) { $commands{*{$_[1]}{NAME}}[PERM] |= LOW_PRIO }
sub Args : ATTR(CODE)    { $commands{*{$_[1]}{NAME}}[ARG] = $_[4] }

sub Private : ATTR(CODE) {
	$commands{*{$_[1]}{NAME}}[PERM] |= PRIVATE_COMMAND;
	$commands{*{$_[1]}{NAME}}[PERM] |= PRIVATE_NOTICE if $_[4] eq 'notice';
	$commands{*{$_[1]}{NAME}}[PERM] |= PRIVATE_PRIVMSG if $_[4] eq 'privmsg';
}

sub Public : ATTR(CODE) {
	$commands{*{$_[1]}{NAME}}[PERM] |= PUBLIC_COMMAND;
	$commands{*{$_[1]}{NAME}}[PERM] |= PUBLIC_NOTICE if $_[4] eq 'notice';
	$commands{*{$_[1]}{NAME}}[PERM] |= PUBLIC_PRIVMSG if $_[4] eq 'privmsg';
}

# this is what you call one hell of a sanity check!

BEGIN {

	sub _check_patch_pci {
		open FILE, $INC{'POE/Component/IRC.pm'} or
			die "Can't open POE::Component::IRC patchee: $!";
		binmode FILE;
		die "\n\033[1m" .
		"             => You aren't using the correct POE::Component::IRC. <=\033[m\007\n\n".
		"Possible reasons:\n\n" .
		"1 - You did not patch POE::Component::IRC.\n" .
		"2 - You patched over an already patched POE::Component::IRC.\n" .
		"3 - You are not using POE::Component::IRC 2.7.\n\n" .
		"Reinstall POE::Component::IRC, and patch it from scratch.\n" .
		"The patch file is located in etc/. See POD for details.\n\n" unless
			Digest::MD5->new->addfile(*FILE)->hexdigest eq
				'8267d47db2e11e764862c210b1a30487';
	}

	_check_patch_pci();
}

1;
