# $Revision: 1.4 $
# $Id: BasicBot.pm,v 1.4 2003/08/28 09:32:33 afoxson Exp $

package Bot::CPAN::BasicBot;

require 5.006;

use strict;
use Carp;
use Exporter;
use POE::Kernel;
use POE::Session;
use POE::Wheel::Run;
use POE::Filter::Line;
use POE::Component::IRC;
use POSIX qw(strftime);

use constant IRCNAME   => "wanna";
use constant ALIASNAME => "pony";

use vars qw(@ISA @EXPORT $VERSION);
@ISA    = qw(Exporter);
@EXPORT = qw(say emote);

($VERSION) = '$Revision: 1.4 $' =~ /\s+(\d+\.\d+)\s+/;

=head1 NAME

Bot::CPAN::BasicBot - simple irc bot baseclass

=head1 SYNOPSIS

  # with all defaults
  Bot::CPAN::BasicBot->new( channels => ["#bottest"] )->run();

  # with all known options
  Bot::CPAN::BasicBot->new( channels => ["#bottest"],

                      servers => [qw(irc.example.com)],
                      port   => "6667",

                      nick      => "basicbot",
                      alt_nicks => ["bbot", "simplebot"],
                      username  => "bot",
                      debug => 0,
                      name      => "Yet Another Bot",

                      ignore_list => [qw(dipsy dadadodo laotse)],

                      store =>
                      Bot::Store::Simple->new(filename => "store.file"),

                      log   =>
                      Bot::Log::Simple->new(filename => "log.file"),
                );

=head1 DESCRIPTION

Basic bot system designed to make it easy to do simple bots, optionally
forking longer processes (like searches) concurrently in the background.

=head2 Main Methods

=over 4

=item new

Creates a new instance of the class.  Name value pairs may be passed
which will have the same effect as calling the method of that name
with the value supplied.

=cut

sub new {
    my $class = shift;
    my $this  = bless {}, $class;

    # call the set methods
    my %args = @_;
    foreach my $method ( keys %args ) {
        if ( $this->can($method) ) {
            $this->$method( $args{$method} );
        } else {
            $this->{$method} = $args{$method};

            #croak "Invalid argument '$method'";
        }
    }

    return $this;
}

=item run

Runs the bot.  Hands the control over to the POE core.

=cut

sub run {
    my $this = shift;

    # yep, we use irc
    POE::Component::IRC->new(IRCNAME)
      or die "Can't instantiate new IRC component!\n";

    # create the callbacks to the object states
    POE::Session->create(
        object_states => [
            $this => {
                _start => "start_state",
                _stop  => "stop_state",

                irc_001         => "irc_001_state",
                irc_msg         => "irc_said_state",
                irc_public      => "irc_said_state",
                irc_ctcp_action => "irc_emoted_state",
                irc_ping        => "irc_ping_state",

                irc_disconnected => "irc_disconnected_state",
                reconnect        => "reconnect_state",
                irc_error        => "irc_error_state",
                irc_socketerr    => "irc_socketerr_state",

                fork_close => "fork_close_state",
                fork_error => "fork_error_state"
            }
        ]
    );

    # and say that we want to recive said messages
    $poe_kernel->post( IRCNAME => register => 'all' );

    # run
    $poe_kernel->run();
}

=item said($args)

This is the main method that you'll want to override in your subclass -
it's the one called by default whenever someone says anything that we
can hear, either in a public channel or to us in private that we
shouldn't ignore.

You'll be passed a reference to a hash that contains the arguments
described below.  Feel free to alter the values of this hash - it
won't be used later on.

=over 4

=item who

Who said it (the nick that said it)

=item channel

The channel in which they said it.  Has special value "msg" if it
was in a message.  Actually, as you can send a message to many
channels at once in the IRC spec, but no-one actually does this
so it's just the first one in the list

=item body

The body of the message (i.e. the actual text)

=item address

The text that indicates how we were addressed.  Contains the string
"msg" for private messages, otherwise contains the string off the text
that was stripped off the front of the message if we were addressed,
e.g. "Nick: ".  Obviously this can be simply checked for truth if you
just want to know if you were addressed or not.

=back

You should return what you want to say.  This can either be a simple
string (which will be sent back to whoever was talking to you as a
message or in public depending on how they were talking) or a hashref
that contains values that are compatible with say (just changing
the body and returning the structure you were passed works very well.)

Returning undef will cause nothing to be said.

=item emoted

This is a secondary method that you may wish to override. In its
default configuration, it will simply pass anything emoted on channel
through to the C<said> handler.

C<emoted> receives the same data hash as C<said>.

=cut

# do nothing implementation
sub said { undef }

# default emoted will pass through to "said"
sub emoted {
    my ( $self, $emoted_hashref ) = @_;
    $self->said($emoted_hashref);
}

=item forkit

This method allows you to fork arbitrary background processes. They
will run concurrently with the main bot, returning their output to a
handler routine. You should call C<forkit> in response to specific
events in your C<said> routine, particularly for longer running
processes like searches, which will block the bot from receiving or
sending on channel whilst they take place if you don't fork them.

C<forkit> takes the following arguments:

=over 4

=item run

A coderef to the routine which you want to run. Bear in mind that the
routine doesn't automatically get the text of the query - you'll need
to pass it in C<arguments> (see below) if you want to use it at all.

Apart from that, your C<run> routine just needs to print its output to
C<STDOUT>, and it will be passed on to your designated handler.

=item handler

Optional. A method name within your current package which we can
return the routine's data to. Defaults to the built-in method
C<say_fork_return> (which simply sends data to channel).

=item body

Optional. Use this to pass on the body of the incoming message that
triggered you to fork this process. Useful for interactive proceses
such as searches, so that you can act on specific terms in the user's
instructions.

=item who

The nick of who you want any response to reach (optional inside a
channel.)

=item channel

Where you want to say it to them in.  This may be the special channel
"msg" if you want to speak to them directly

=item address

Optional.  Setting this to a true value causes the person to be
addressed (i.e. to have "Nick: " prepended to the front of returned
message text if the response is going to a public forum.

=item arguments

Optional. This should be an anonymous array of values, which will be
passed to your C<run> routine. Bear in mind that this is not
intelligent - it will blindly spew arguments at C<run> in the order
that you specify them, and it is the responsibility of your C<run>
routine to pick them up and make sense of them.

=back

=cut

sub forkit {
    my $this = shift;
    my $args;
    if ( $#_ > 1 ) {
        my %args = @_;
        $args = \%args;
    } else {
        $args = shift;
    }

    return undef unless $args->{run};

    $args->{handler}   = $args->{handler}   || "fork_said";
    $args->{arguments} = $args->{arguments} || [];

    #install a new handler in the POE kernel pointing to
    # $self->{$args{handler}}
    $poe_kernel->state( $args->{handler}, $this );

    my $run;
    if ( ref( $args->{run} ) =~ /^CODE/ ) {
        $run =
          sub { &{ $args->{run} }( $args->{body}, @{ $args->{arguments} } ) };
    } else {
        $run = $args->{run};
    }

    my $wheel = POE::Wheel::Run->new(
        Program      => $run,
        StdoutFilter => POE::Filter::Line->new(),
        StderrFilter => POE::Filter::Line->new(),
        StdoutEvent  => "$args->{handler}",
        StderrEvent  => "fork_error",
        CloseEvent   => "fork_close"
    );

    # store the wheel object in our bot, so we can retrieve/delete easily

    $this->{forks}->{ $wheel->ID } = {
        wheel => $wheel,
        args  => {
            channel => $args->{channel},
            who     => $args->{who},
            address => $args->{address},
            data    => $args->{data},
            userhost => $args->{userhost},
        }
    };
    return undef;
}

=item say

Say something to someone.  You should pass the following arguments:

=over 4

=item who

The nick of who you are saying this to (optional inside a channel.)

=item channel

Where you want to say it to them in.  This may be the special channel
"msg" if you want to speak to them directly

=item body

The body of the message.  I.e. what you want to say.

=item address

Optional.  Setting this to a true value causes the person to be
addressed (i.e. to have "Nick: " prepended to the front of the message
text if this message is going to a pulbic forum.

=back

C<say> automatically calls c<cannonical_nick> to resolve nicks to
the current nick for someone, so even if they've changed their nick
when you say something it should (assuming POE gets round to sending
it in time) be sent to the right person.

You can also make non-OO calls to C<say>, which will be interpreted as
coming from a process spawned by C<forkit>. The routine will serialise
any data it is sent, and throw it to STDOUT, where POE::Wheel::Run can
pass it on to a handler.

=cut

sub say {

    # If we're called without an object ref, then we're handling saying
    # stuff from inside a forked subroutine, so we'll freeze it, and toss
    # it out on STDOUT so that POE::Wheel::Run's handler can pick it up.
    if ( !ref( $_[0] ) ) {
        print $_[0] . "\n";
        return 1;
    }

    # Otherwise, this is a standard object method

    my $this = shift;
    my $args;
    if ( $#_ > 1 ) {
        my %args = @_;
        $args = \%args;
    } else {
        $args = shift;
    }

    my $body = $args->{body};

    # add the "Foo: bar" at the start
    $body = "$args->{who}: $body"
      if ( $args->{channel} ne "msg" and $args->{address} );

    # work out who we're going to send the message to
    my $who = ( $args->{channel} eq "msg" ) ? $args->{who} : $args->{channel};

    unless ( $who && $body ) {
        print STDERR "Can't PRIVMSG without target and body\n";
        print STDERR " who = '$who'\n body = '$body'\n";
        return;
    }

    # post an event that will send the message
    $poe_kernel->post( IRCNAME, 'privmsg', $who, $body );
}

=item emote

C<emote> will return data to channel, but emoted (as if you'd said
"/me writes a spiffy new bot" in most clients). It takes the same arguments as C<say>, listed above.

=cut

sub emote {

    # If we're called without an object ref, then we're handling emoting
    # stuff from inside a forked subroutine, so we'll freeze it, and
    # toss it out on STDOUT so that POE::Wheel::Run's handler can pick
    # it up.
    if ( !ref( $_[0] ) ) {
        print $_[0] . "\n";
        return 1;
    }

    # Otherwise, this is a standard object method

    my $this = shift;
    my $args;
    if ( $#_ > 1 ) {
        my %args = @_;
        $args = \%args;
    } else {
        $args = shift;
    }

    my $body = $args->{body};

    # Work out who we're going to send the message to
    my $who =
      ( $args->{channel} eq "msg" )
      ? $args->{who}
      : $args->{channel};

    # post an event that will send the message
    # if there's a better way of sending actions i'd love to know - jw
    # me too; i'll look at it in v0.5 - sb

    $poe_kernel->post( IRCNAME, 'privmsg', $who, "\cAACTION " . $body . "\cA" );
}

=item fork_said

C<fork_said> is really an internal method, the default handler
for output from a process forked by C<forkit>. It actually takes
its input from a non-object call to C<say>, thaws the data, picks
up arguments, and throws them back at C<say> again. Don't ask - this
is the way POE::Wheel::Run works, and this jiggery-pokery gives us a
nice object interface.

=cut

sub fork_said {
    my ( $this, $body, $wheel_id ) = @_[ 0, ARG0, ARG1 ];
    chomp($body);    # remove newline necessary to move data;

    # pick up the default arguments we squirreled away earlier
    my $args = $this->{forks}->{$wheel_id}->{args};
    $args->{body} = $body;

    $this->say($args);
}

=item help

This is the other method that you should override.  This is the text
that the bot will respond to if someone simply says help to it.  This
should be considered a special case which you should not attempt
to process yourself.  Saying help to a bot should have no side effects
whatsoever apart from returning this text.

=cut

sub help { "Sorry, this bot has no interactive help." }

=item connected

An optional method to override, gets called after we have connected
to the server

=cut

sub connected { undef }

=back

=head2 Access Methods

Get or set methods.  Changing most of these values when connected
won't cause sideffects.  e.g. changing the server will not
cause a disconnect and a reconnect to another server.

Attributes that accept multiple values always return lists and
either accept an arrayref or a complete list as an argument.

=item servers

The servers we're going to connect to. One will be picked randomly. Defaults to
"london.rhizomatic.net".

=cut

sub servers {
    my $this = shift;
    if (@_) {
		my @args = (ref $_[0] eq "ARRAY") ? @{$_[0]} : @_;
		$this->{servers} = \@args;
	}
	@{$this->{servers} || ["london.rhizomatic.net"]}
}

=item port

The port we're going to use.  Defaults to "6667"

=cut

sub port {
    my $this = shift;
    $this->{port} = shift if @_;
    return $this->{port} || "6667";
}

=item nick

The nick we're going to use.  Defaults to five random letters
and numbers followed by the word "bot"

=cut

sub nick {
    my $this = shift;
    $this->{nick} = shift if @_;
    return $this->{nick} ||= _random_nick();
}

sub _random_nick {
    my @things = ( 'a' .. 'z' );
    return join '', ( map { @things[ rand @things ] } 0 .. 4 ), "bot";
}

=item alt_nicks

Alternate nicks that this bot will be known by.  These are not nicks
that the bot will try if it's main nick is taken, but rather other
nicks that the bot will recognise if it is addressed in a public
channel as the nick.  This is useful for bots that are replacements
for other bots...e.g, your bot can answer to the name "infobot: "
even though it isn't really.

=cut

sub alt_nicks {
    my $this = shift;
    if (@_) {

        # make sure we copy
        my @args = ( ref $_[0] eq "ARRAY" ) ? @{ $_[0] } : @_;
        $this->{alt_nicks} = \@args;
    }
    @{ $this->{alt_nicks} || [] };
}

=item username

The username we'll claim to have at our ip/domain.  By default this
will be the same as our nick.

=cut

sub username {
    my $this = shift;
    $this->{username} = shift if @_;
    $this->{username} or $this->nick;
}

sub debug {
	my $this = shift;
	$this->{debug} = shift if @_;
	return $this->{debug} || 0;
}

=item name

The name that the bot will identify itself as.  Defaults to
"$nick bot" where $nick is the nick that the bot uses.

=cut

sub name {
    my $this = shift;
    $this->{name} = shift if @_;
    $_[0]->{name} or $this->nick . " bot";
}

=item channels

The channels we're going to connect to.

=cut

sub channels {
    my $this = shift;
    if (@_) {

        # make sure we copy
        my @args = ( ref $_[0] eq "ARRAY" ) ? @{ $_[0] } : @_;
        $this->{channels} = \@args;
    }
    @{ $this->{channels} || [] };
}

=item quit_message

The quit message.  Defaults to "Bye".

=cut

sub quit_message {
    my $this = shift;
    $this->{quit_message} = shift if @_;
    defined( $this->{quit_message} ) ? $this->{quit_message} : "Bye";
}

=item ignore_list

The list of irc nicks to ignore B<public> messages from (normally
other bots.)  Useful for stopping bot cascades.

=cut

sub ignore_list {
    my $this = shift;
    if (@_) {

        # make sure we copy
        my @args = ( ref $_[0] eq "ARRAY" ) ? @{ $_[0] } : @_;
        $this->{ignore_list} = \@args;
    }
    @{ $this->{ignore_list} || [] };
}

=head2 States

These are the POE states that we register in order to listen
for IRC events.

=over 4

=item start_state

Called when we start.  Used to fire a "connect to irc server event"

=cut

sub start_state {
    my ( $this, $kernel, $session ) = @_[ OBJECT, KERNEL, SESSION ];

    $this->log("Control session start\n");

    # Make an alias for our session, to keep it from getting GC'ed.
    $kernel->alias_set(ALIASNAME);

    # Ask the IRC component to send us all IRC events it receives. This
    # is the easy, indiscriminate way to do it.
    $kernel->post(IRCNAME, 'register', 'all');

	my $server = ($this->servers)[int(rand(scalar $this->servers))];
	$this->log("Attempting to connect to: $server\n");

    # Setting Debug to 1 causes P::C::IRC to print all raw lines of text
    # sent to and received from the IRC server. Very useful for debugging.
    $kernel->post(IRCNAME,'connect',
        {
            Debug    => $this->debug,
            Nick     => $this->nick,
            Server   => $server,
            Port     => $this->port,
            Username => $this->username,
            Ircname  => $this->name,
        }
    );
    $kernel->delay('reconnect', 500);

}

sub reconnect_state {
    my ( $this, $kernel, $session ) = @_[ OBJECT, KERNEL, SESSION ];

    $this->log("I think I've lost the server. restarting..\n");

    $kernel->call( IRCNAME, 'disconnect' );
    $kernel->call( IRCNAME, 'shutdown' );
    POE::Component::IRC->new(IRCNAME);
    $kernel->post( IRCNAME, 'register', 'all' );

	my $server = ($this->servers)[int(rand(scalar $this->servers))];
	$this->log("Attempting to connect to: $server\n");

    $kernel->post(IRCNAME, 'connect',
        {
            Debug    => $this->debug,
            Nick     => $this->nick,
            Server   => $server,
            Port     => $this->port,
            Username => $this->username,
            Ircname  => $this->name,
        }
    );
    $kernel->delay('reconnect', 500);
}

=item stop_state

Called when we're stopping.  Shutdown the bot correctly.

=cut

sub stop_state {
    my ( $this, $kernel ) = @_[ OBJECT, KERNEL ];

    $this->log("Control session stopped.\n");

    $kernel->post( IRCNAME, 'quit', $this->quit_message );
    $kernel->alias_remove(ALIASNAME);
}

=item irc_001_state

Called when we connect to the irc server.  This is used to tell
the irc server that we'd quite like to join the channels.

We also ignore ourselves.  We don't want to hear what we have to say.

=cut

sub irc_001_state {
    my ( $this, $kernel ) = @_[ OBJECT, KERNEL ];

    $this->log("IRC server ready\n");

    # ignore all messages from ourselves
    $kernel->post( IRCNAME, 'mode', $this->nick, '+i' );

    # connect to the channel
    foreach my $channel ( $this->channels ) {
        $this->log("Trying to connect to '$channel'\n");
        $kernel->post( IRCNAME, 'join', $channel );
    }

    $this->connected();
}

=item irc_disconnected_state

Called if we are disconnected from the server.  Logs the error and
then reconnects.

=cut

sub irc_disconnected_state {
    my ( $this, $server ) = @_[ OBJECT, ARG0 ];
    $this->log("Lost connection to server $server.\n");

    #  die "IRC Disconnect: $server";
}

=item irc_error_state

Called if there is an irc server error.  Logs the error and then dies.

=cut

sub irc_error_state {
    my ( $this, $err ) = @_[ OBJECT, ARG0 ];
    $this->log("Server error occurred! $err\n");

    #  die "IRC Error: $err";
}

sub irc_socketerr_state {
	my ($this, $err) = @_[OBJECT, ARG0];
	$this->log("Socket error occured! $err\n");
	die "Socket Error: $err";
}

=item irc_kicked_state

Called if we get kicked.  If we're kicked then it's best to do
nothing.  Bots are normally called in wrapper that restarts them
if we die, which may end us up in a busy loop.  Anyway, if we're not
wanted, the best thing to do would be to hang around off channel.

=cut

sub irc_kicked_state {
    my ( $this, $err ) = @_[ OBJECT, ARG0 ];
}

=item irc_join_state

Called if someone joins.  Used for nick tracking

=cut

sub irc_join_state {
    my ( $this, $nick ) = @_[ OBJECT, ARG0 ];
}

=item irc_nick_state

Called if someone changes nick.  Used for nick tracking

=cut

sub irc_nick_state {
    my ( $this, $nick, $newnick ) = @_[ OBJECT, ARG0, ARG1 ];
}

=item irc_said_state

Called if we recieve a private or public message.  This
formats it into a nicer format and calls 'said'

=cut

sub irc_said_state {
    irc_received_state( 'said', 'say', @_ );
}

=item irc_emoted_state

Called if someone "emotes" on channel, rather than directly saying
something. Currently passes the emote striaght to C<irc_said_state>
which deals with it as if it was a spoken phrase.

=cut

sub irc_emoted_state {
    irc_received_state( 'emoted', 'emote', @_ );
}

=item irc_received_state

Called by C<irc_said_state> and C<irc_emoted_state> in order to format
channel input into a more copable-with format.

=cut

sub irc_received_state {
    my $received = shift;
    my $respond  = shift;
    my ( $this, $nick, $to, $body ) = @_[ OBJECT, ARG0, ARG1, ARG2 ];

    my $return;

    my $mess = {};

    # work out who it was from
    $mess->{userhost} = $nick;
    $mess->{who} = $this->nick_strip($nick);

	return undef if $this->ignore_nick($mess->{who});

    # right, get the list of places this message was
    # sent to and work out the first one that we're
    # either a memeber of is is our nick.
    # The IRC protocol allows messages to be sent to multiple
    # targets, which is pretty clever. However, noone actually
    # /does/ this, so we can get away with this:

    my $channel = $to->[0];
    if ($this->nick =~ /^$channel$/i) {
        $mess->{channel} = "msg";
        $mess->{address} = "msg";
    } else {
        $mess->{channel} = $channel;
    }

    # okay, work out if we're addressed or not

    $mess->{body} = $body;
    unless ( $mess->{channel} eq "msg" ) {
        my $nick = $this->nick;
        ( $mess->{address} ) = $mess->{body} =~ /^(\Q$nick\E[:,]\s)/i;
		$mess->{body} =~ s/^(\Q$nick\E[:,]\s)//i if $mess->{address};

        foreach $nick ( $this->alt_nicks ) {
            last if $mess->{address};

            ( $mess->{address} ) = $mess->{body} =~ /^(\Q$nick\E[:,]\s)/i;
				$mess->{body} =~ s/^(\Q$nick\E[:,]\s)//i if $mess->{address};
        }
    }

    # strip off whitespace before and after the message
    $mess->{body} =~ s/^\s+//;
    $mess->{body} =~ s/\s+$//;

    # okay, we got this far.  Better log this.  This needs changing
    # to a nice format.  Oooh, I could spit out sax events... (mf)

  if ($mess->{address}) {
  if ($mess->{channel} eq 'msg') {
    $this->log("=> /msg ${\($this->nick)} $mess->{body} (from $mess->{who}) <=\n");
  }
  else {
    $this->log("=> $mess->{who}:${\($mess->{address} ? ' ' . $mess->{address} : '')}$mess->{body} (from $mess->{channel}) <=\n");
  }
  }

    # check if someone was asking for help
    #if ( $mess->{address} && ( $mess->{body} =~ /^help/i ) ) {
    #    $this->log("Invoking help for '$mess->{who}'\n");
    #    $mess->{body} = $this->help($mess);
    #    $this->say($mess);
    #    return;
    #}

    # okay, call the said/emoted method
    $respond = $this->$received($mess);

    ### what did we get back?

    # nothing? Say nothing then
    return unless defined($return);

    # a string?  Say it how we were addressed then
    unless ( ref($return) ) {
        $mess->{body} = $return;
        $this->$respond($mess);
        return;
    }

    # just say what we were handed back
    $this->$respond($return);
}

=item irc_ping_state

The most reliable way I've found of doing auto-server-rejoin is to listen for
pings. Every ping we get, we put off rejoining the server for another few mins.
If we haven't heard a ping in a while, the rejoin code will get called.

=cut

sub irc_ping_state {
    my ( $this, $kernel, $heap ) = @_[ OBJECT, KERNEL, HEAP ];
    $this->log("PING\n");
    $kernel->delay( 'reconnect', 500 );
}

=item fork_close_state

Called whenever a process forked by C<POE::Wheel::Run> (in C<forkit>)
terminates, and allows us to delete the object and associated data
from memory.

=cut

sub fork_close_state {
    my ( $this, $wheel_id ) = @_[ 0, ARG0 ];

    #warn "received close event from wheel $wheel_id\n";
    delete $this->{forks}->{$wheel_id};
}

=item fork_error_state

Called if a process forked by C<POE::Wheel::Run> (in C<forkit>) hits
an error condition for any reason. Does nothing, but can be overloaded
in derived classes to be more useful

=cut

sub fork_error_state { }

=back

=head2 Other States

Bot::CPAN::BasicBot implements AUTOLOAD for sending arbitrary states to the
underlying POE::Component::IRC compoment. So for a $bot object, sending

    $bot->foo("bar");

is equivalent to

    $poe_kernel->post(BASICBOT_ALIAS, "foo", "bar");

=cut

sub AUTOLOAD {
    my $this = shift;
    our $AUTOLOAD;
    $AUTOLOAD =~ s/.*:://;
    $poe_kernel->post( IRCNAME, $AUTOLOAD, @_ );
}

=head2 Methods

=over 4

=item log

Logs the message.  Calls the logging module if one was initilised,
otherwise simple prints the message to STDERR.

=cut

sub log {
    my $this = shift;
    my $text = shift;

    if ( $this->{log} ) {
        $this->{log}->log( time . " $text" );
    } else {
		my $dt = POSIX::strftime("%y-%m-%d %H:%M:%S", localtime(time));
        print STDERR "$dt: $text";
    }
}

=item get($key) or get($storename, $key)

Gets the key from the store.  Uses the store module loaded if
initilised, otherwise uses an internal hash.  By default
uses the "main" store.

=cut

sub get {
    my $this      = shift;
    my $key       = pop;
    my $storename = pop || "main";

    if ( $this->{store} ) {
        return $this->{store}->get( $storename, $key );
    } elsif ( $this->{tempstore}{$storename} ) {
        $this->{tempstore}{$storename}{$key};
    } else {
        return undef;
    }
}

=item set($key, $value) or set($storename, $key, $value)

Sets the key in the store.  Uses the store module loaded if
initilised, otherwise uses an internal hash.

=cut

sub set {
    my $this      = shift;
    my $value     = pop;
    my $key       = pop;
    my $storename = pop || "main";

    if ( $this->{store} ) {
        return $this->{store}->get( $storename, $key );
    }

    $this->{tempstore}{$storename} = {}
      unless ( $this->{tempstore}{$storename} );

    $this->{tempstore}{$storename}{$key} = $value;
}

sub delete
{
  my $this      = shift;
  my $key       = pop;
  my $storename = pop || "main";

  if ($this->{store})
  {
    return $this->{store}->delete($storename,$key)
  }
  elsif ($this->{tempstore}{ $storename })
  {
    delete $this->{tempstore}{ $storename }{ $key };
  }
  else
  {
    return undef;
  }
}


=item ignore_nick($nick)

Return true if this nick should be ignored.  Ignores anything in
the ignore list or with a nick ending in "bot".

=cut

sub ignore_nick {
    local $_;
    my $this = shift;
    my $nick = shift;
    return grep { $nick eq /^$_$/i } @{ $this->{ignore_list} };
}

=item nick_strip

Takes a nick and hostname (of the form "nick!hostname") and
returns just the nick

=cut

sub nick_strip {
    my $this     = shift;
    my $combined = shift;
    my ($nick) = $combined =~ m/(.*?)!/;

    return $nick;
}

=back

=head1 AUTHOR

Tom Insam E<lt>tom@jerakeen.orgE<gt>

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=head1 CREDITS

The initial version of Bot::CPAN::BasicBot was written by Mark Fowler,
and many thanks are due to him.

Nice code for dealing with emotes thanks to Jo Walsh.

Various patches from Tom Insam, including much improved rejoining,
AUTOLOAD stuff, better interactive help, and a few API tidies.

Maintainership for a while was in the hands of Simon Kent
E<lt>simon@hitherto.netE<gt>. Don't know what he did. :-)

=head1 SYSTEM REQUIREMENTS

Bot::CPAN::BasicBot is based on POE, and really needs the latest version as
of writing (0.22), since POE::Wheel::Run (used for forking) is still
under development, and the interface recently changed. With earlier
versions of POE, forking will not work, and the makefile process will
carp if you have < 0.22. Sorry.

You also need POE::Component::IRC.

=head1 BUGS

During the make, make test make install process, POE will moan about
its kernel not being run. I'll try and gag it in future releases, but
hey, release early, release often, and it's not a fatal error. It just
looks untidy.

Don't call your bot "0".

Nick tracking blatantly doesn't work yet.  In Progress.

C<fork_error_state> handlers sometimes seem to cause the bot to
segfault. I'm not yet sure if this is a POE::Wheel::Run problem, or a
problem in our implementation.

=head1 TODO

Proper tests need to be written. I'm envisaging a test suite that will
connect a Bot::CPAN::BasicBot instance to a test channel on a server, and
then connect another user who can interface with the bot and check its
responses. I have a basic stub for this, but as of writing, nothing
more :( It will be done asap, I promise, and will then be forked to
provide a more comprehensive test suite for building bots that can,
for example, duplicate the functionality of an infobot.

Mark Fowler has done some work on making BasicBot work with other
messaging systems, in particular Jabber. It looks like this will be
combined with Bot::CPAN::BasicBot, and become a new module,
Bot::Framework. Bot::CPAN::BasicBot is, after all, supposed to be basic :)

=head1 SEE ALSO

POE

POE::Component::IRC

Possibly Infobot, at http://www.infobot.org

=cut

1;
