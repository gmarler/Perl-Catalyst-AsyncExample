package AsyncExample::Controller::IOAsync::Echo;

use v5.18.1;

use base 'Catalyst::Controller';
use Protocol::WebSocket::Handshake::Server;
use Net::Async::WebSocket::Server;
use Net::Async::WebSocket::Protocol;
use Data::Dumper;

sub start : ChainedParent
 PathPart('echo') CaptureArgs(0) { }

sub index :Chained('start') PathPart('') Args(0)
{
  my ($self, $c) = @_;
  my $url = $c->uri_for_action($self->action_for('ws'));

  $url->scheme('ws');
  $c->stash(websocket_url => $url);
  $c->forward($c->view('HTML'));
}

sub ws :Chained('start') Args(0)
{
  my ($self, $c) = @_;
  my $io = $c->req->io_fh;

  say "FILE DESCRIPTOR FOR \$io:      " . $io->fileno;
  say "FILE DESCRIPTOR FOR psgix.io: " . $c->req->env->{'psgix.io'}->fileno;

  # my $listen_socket = $c->req->env->{'psgix.io'};

  # say "CLIENT    SOCKET: $io";
  # say "LISTENING SOCKET: $listen_socket";
  
  # At this point, the catalyst server has already accepted the client's
  # connection request, and probably received the attempt to upgrade the
  # connection to a WebSocket on $io - that data is now pending, so if we
  # create an IO::Async::Stream here, the on_read handler won't be triggered
  # at this point.  We have to explicitly read the handshake off the socket
  # now.

  my $hs = Protocol::WebSocket::Handshake::Server
    ->new_from_psgi($c->req->env);

  if ( ! $hs->is_body ) {
    say "WebSocket Handshake failed before reading from client: " .
        $hs->error;
  }

  # Parse the incoming handshake from the client
  $hs->parse($io);

  if ( ! $hs->is_done ) {
    say "WebSocket Handshake with client failed " .
        $hs->error;
  }

  # Now we create the IO::Async::Stream, with its on_read handler
  my $web_socket =
    IO::Async::Stream->new(
      handle => $io,
      on_read => sub {
        my ($stream, $buff, $eof) = @_;
        say "READING FROM CLIENT SOCKET";
        if ($hs->is_done) {
          (my $frame = $hs->build_frame)->append($$buff);
          while (my $message = $frame->next) {
            $message = $hs->build_frame(buffer => $message)->to_bytes;
            $stream->write($message);
          }
          return 0;
        } else {
          say "WE SHOULD NEVER GET HERE";
          #$hs->parse($$buff);
          #$stream->write($hs->to_string);
          #$stream->write($hs->build_frame(buffer => "Echo Initiated")->to_bytes); 
        }
      },
      on_closed => sub {
        say "on_closed EVENT RECEIVED: " . scalar(@_) . " ARGS RECEIVED";
        my ($stream) = @_;
        say "CLOSING WebSocket CONNECTION";
        $c->req->env->{'io.async.loop'}->remove( $stream );
      },
    );

  # Now the $web_socket handle exists, we write the handshake response out to the
  # client.
  
  if ( $hs->is_done ) {
    say "COMPLETING WebSocket HANDSHAKE WITH CLIENT";
    $web_socket->write($hs->to_string);
    $web_socket->write($hs->build_frame(buffer => "Echo Initiated")->to_bytes);
  } else {
    say "THE WebSocket HANDSHAKE FAILED!";
  }

  #my $server = Net::Async::WebSocket::Server->new(
  #on_client => sub {
  #  my ($self, $client) = @_;
  #  say "CLIENT CONNECTED";
  #  $self->send_frame( 'Echo Initiated' );

  #  $client->configure(
  #    on_frame => sub {
  #      my ( $self, $frame ) = @_;
  #      say "FRAME RECEIVED";
  #      $self->send_frame( $frame );
  #    },
  #  );
  #},
  #on_accept => sub {
  #  say "Entering on_accept with args: " . Dumper( \@_ );
  #  my ($self) = shift;
  #  say "Accepting connection from WebSocket client";

  #  Net::Async::WebSocket::Protocol->new( handle => $io );
  #},
  #);


  #$server->add_child(
  #  Net::Async::WebSocket::Protocol->new( handle => $io)
  #);
  #
  
  #$server->on_accept(
  #  Net::Async::WebSocket::Protocol->new( handle => $io )
  #);

  #$c->req->env->{'io.async.loop'}->add( $server );

  $c->req->env->{'io.async.loop'}->add( $web_socket );
}


1;
