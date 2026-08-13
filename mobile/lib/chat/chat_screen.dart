import 'package:flutter/material.dart';
import 'chat_socket_client.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.socketClient,
    required this.matchId,
  });

  final ChatSocketClient socketClient;
  final String matchId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <String>[];
  final _inputController = TextEditingController();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    widget.socketClient.joinMatch(widget.matchId);
    widget.socketClient.onHistory((history) {
      if (!mounted || history is! List) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(history.map((m) => (m as Map)['content'] as String));
      });
    });
    widget.socketClient.onNewMessage((message) {
      if (!mounted) return;
      setState(() => _messages.add(message['content'] as String));
    });
    widget.socketClient.onError((error) {
      if (!mounted) return;
      final message = error is Map ? error['message']?.toString() : null;
      setState(() => _errorMessage = message ?? '채팅 오류가 발생했습니다');
    });
    widget.socketClient.onConnectError((error) {
      if (!mounted) return;
      setState(() => _errorMessage = '채팅 서버에 연결할 수 없습니다');
    });
  }

  void _send() {
    widget.socketClient.sendMessage(widget.matchId, _inputController.text);
    _inputController.clear();
  }

  @override
  void dispose() {
    widget.socketClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_errorMessage != null)
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          Expanded(
            child: ListView(children: _messages.map((m) => Text(m)).toList()),
          ),
          Row(
            children: [
              Expanded(child: TextField(controller: _inputController)),
              IconButton(
                key: const Key('sendButton'),
                icon: const Icon(Icons.send),
                onPressed: _send,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
