# $Revision: 1.3 $
# $Id: Glue.pm,v 1.3 2006/07/04 07:19:51 afoxson Exp $
#
# Bot::CPAN::Glue - Deep magic for Bot::CPAN
# Copyright (c) 2003 Adam J. Foxson. All rights reserved.

# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.

package Bot::CPAN::Glue;

require 5.008;

use strict;
use warnings;
use POE;
use vars qw(@ISA @EXPORT $VERSION %commands);
use Bot::CPAN::BasicBot;
use Error qw(:try);
use Bot::CPAN::E::NoDist;
use Bot::CPAN::E::NoAuth;
use Bot::CPAN::E::NoMod;
use Bot::CPAN::E::Unknown;
use Class::Phrasebook;
use constant NOT_A_COMMAND   => 0;
use constant PUBLIC_COMMAND  => 1<<0;
use constant PRIVATE_COMMAND => 1<<1;
use constant FORK            => 1<<2;
use constant LOW_PRIO        => 1<<3;
use constant PUBLIC_NOTICE   => 1<<4;
use constant PUBLIC_PRIVMSG  => 1<<5;
use constant PRIVATE_NOTICE  => 1<<6;
use constant PRIVATE_PRIVMSG => 1<<7;
use constant ADMIN_CMD       => 1<<8;
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
	'__CALLER__::Admin'   => __PACKAGE__,
};

($VERSION) = '$Revision: 1.3 $' =~ /\s+(\d+\.\d+)\s+/;
@ISA = qw(Bot::CPAN::BasicBot);

# this is the command handler, here we are ultimately responsible for
# accepting or rejecting a command
sub _command {
	my ($self, $message) = @_;

	return unless
		my ($command, $module_or_author) = $self->_parse_command($message);
	return unless
		$self->_verify_auth($message, $command);
	return unless
		$self->_verify_usage($message, $command, $module_or_author);

	$self->set('requests', $self->get('requests') + 1);
	$message->{data} = $command;
	$self->log("DEBUG: _command: $command, $module_or_author\n") if
		$self->debug;
    try {
	    $self->_dispatch($message, $module_or_author);
    }
    catch Bot::CPAN::E::NoDist with {
        my $E = shift;
        $self->_print($message, $self->phrase('NO_DISTRIBUTION', {distribution => $E->{'-text'}}));
    }
    catch Bot::CPAN::E::NoMod with {
        my $E = shift;
        $self->_print($message, $self->phrase('NO_MODULE', {module => $E->{'-text'}}));
    }
    catch Bot::CPAN::E::NoAuth with {
        my $E = shift;
        $self->_print($message, $self->phrase('NO_AUTHOR', {author => $E->{'-text'}}));
    }
    catch Bot::CPAN::E::Unknown with {
        $self->_print($message, $self->phrase('UNKNOWN'));
    }
    catch Error::Simple with {
        my $E = shift;
        my $error = $E->{'-text'};
        my $file = $E->{'-file'};
        my $line = $E->{'-line'};
        $self->log("DEBUG: COMMAND FAILURE: $error at $file line $line.\n");
        $self->_print($message, $self->phrase('COMMAND_FAILURE'));
    };
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
                address => 1,
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
    # sent internal package info. this ensures that the user gets
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

	$type .= 'lo' if $command and defined $commands{$command}[PERM] and
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
			$key eq 'nickserv_password' ||
			$key eq 'adminhost' ||
			$key eq 'reload_indices_interval' ||
			$key eq 'policy' ||
			$key eq 'search_max_results' ||
			$key eq 'inform_channel_of_new_ratings' ||
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
	$upstream->set('nickserv_password', undef);
	$upstream->set('adminhost', qr/\b\B/); # default impossible match, Fletch++
	$upstream->set('search_max_results', 20);
	$upstream->set('group', 'perl.cpan.testers');
	$upstream->set('reload_indices_interval', 300);
	$upstream->set('inform_channel_of_new_uploads', 60);
	$upstream->set('inform_channel_of_new_ratings', 60);
	$upstream->set('policy', {});

	while (my ($key, $value) = splice @my_args, 0, 2) {
		$upstream->set($key, $value);
	}

	$upstream->_verify_policy();

	# mix in the phrasebook
	my $pm = $INC{'Bot/CPAN.pm'};
	$pm =~ s/\.pm//;
	my $pb = Class::Phrasebook->new(undef, "$pm/phrases.xml");

	die "Unable to load phrasebook.\n" unless defined $pb;

	$pb->remove_new_lines(1);
	$pb->load("EN");
	$upstream->set('pb', $pb);

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
			(?:\s+(?:for|from|of|on|to|contains))?
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

    return;
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
				$message->{body} = "'$command' is a channel only command";
				$self->_return($message);
				return;
			}
			elsif ($commands{$command}[PERM] & PRIVATE_COMMAND) {
				$message->{body} = "'$command' is a /msg only command";
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

sub _verify_auth {
	my ($self, $message, $command) = @_;

	if (defined $commands{$command}[PERM] &&
		$commands{$command}[PERM] & ADMIN_CMD) {
		my $adminhost = $self->get('adminhost');
		if ($message->{userhost} =~ /$adminhost/) {
			return 1;
		}
		else {
			$self->log("$message->{userhost} tried to use admin command $command\n");
			$message->{body} = "'$command' is an admin only command";
			$self->_return($message);
			return;
		}
	}

	return 1;
}

sub phrase {
	my $self = shift;
	my ($filename, $line, $caller) = (caller(1))[1..3];
	my $actual = shift if not $caller;
	my ($phrase, $subphrase);
	my $pb = $self->get('pb');

	if (@_) {
		if (ref $_[0] and ref $_[0] eq 'HASH') {
			$caller = $actual if $actual;
			unless ($phrase = $pb->get($caller, @_)) {
				$phrase = __PACKAGE__ . ": phrase not found for " .
					"$caller with hash arg at $filename:$line";
			}
		}
		else {
			$subphrase = shift;

			if ($subphrase eq uc($subphrase)) {
				$subphrase = $actual if $actual;
				unless ($phrase = $pb->get($subphrase, @_)) {
					$phrase = __PACKAGE__ . ": phrase not found for " .
						"global $subphrase at $filename:$line";
				}
			}
			else {
				if ($actual) {
					$caller = $actual;
				}
				else {
					$caller .= "($subphrase)";
				}
				unless ($phrase = $pb->get($caller, @_)) {
					$phrase = __PACKAGE__ . ": phrase not found for " .
						"$caller($subphrase) with args at $filename:$line";
				}
			}
		}
	}
	else {
		$caller = $actual if $actual;
		unless ($phrase = $pb->get($caller)) {
			$phrase = __PACKAGE__ . ": phrase not found for " .
				"$caller without args at $filename:$line";
		}
	}

	$phrase =~ s/^\s+//;
	$phrase =~ s/\s+$//;

	return $phrase;
}

# and here are the attribute handlers

sub Fork : ATTR(CODE)    { $commands{*{$_[1]}{NAME}}[PERM] |= FORK }
sub Help : ATTR(CODE)    { $commands{*{$_[1]}{NAME}}[HELP] = $_[4] }
sub LowPrio : ATTR(CODE) { $commands{*{$_[1]}{NAME}}[PERM] |= LOW_PRIO }
sub Admin : ATTR(CODE)   { $commands{*{$_[1]}{NAME}}[PERM] |= ADMIN_CMD }
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

1;
