import 'package:socket_io_client/socket_io_client.dart' as io;

/// Thin wrapper around a Socket.IO connection to the chat gateway.
///
/// The gateway (`backend/src/chat/chat.gateway.ts`) authenticates the
/// connection itself via the Socket.IO handshake `auth` payload — it reads
/// `client.handshake.auth.token`, verifies it as a JWT, and disconnects the
/// socket immediately if the token is missing or invalid
/// (`handleConnection`). There is no separate login step over the socket.
///
/// Because the server derives the authenticated user id from the JWT
/// (`client.data.userId`) for both `joinMatch` and `sendMessage`, those
/// events only need to carry `matchId` (and `content` for sending a
/// message) — the server does not read a `userId`/`senderId` field from
/// the payload.
class ChatSocketClient {
  ChatSocketClient(String baseUrl, String accessToken) {
    _socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .build(),
    );
  }

  late final io.Socket _socket;

  void joinMatch(String matchId) {
    _socket.emit('joinMatch', {'matchId': matchId});
  }

  void sendMessage(String matchId, String content) {
    _socket.emit('sendMessage', {'matchId': matchId, 'content': content});
  }

  void onNewMessage(void Function(dynamic message) handler) {
    _socket.on('newMessage', handler);
  }

  void dispose() {
    _socket.dispose();
  }
}
