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

  @override
  void initState() {
    super.initState();
    widget.socketClient.joinMatch(widget.matchId);
    widget.socketClient.onNewMessage((message) {
      setState(() => _messages.add(message['content'] as String));
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
