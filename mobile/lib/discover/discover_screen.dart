import 'package:flutter/material.dart';
import 'discover_repository.dart';
import 'swipe_card.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.repository,
    required this.candidateUserId,
    required this.candidateName,
  });

  final DiscoverRepository repository;
  final String candidateUserId;
  final String candidateName;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  bool? _matched;
  String? _errorMessage;

  Future<void> _like() async {
    try {
      final matched = await widget.repository.swipe(widget.candidateUserId, true);
      setState(() {
        _matched = matched;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _pass() async {
    try {
      await widget.repository.swipe(widget.candidateUserId, false);
      setState(() => _errorMessage = null);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: SwipeCard(name: widget.candidateName)),
          if (_matched == true) const Text("It's a match!"),
          if (_errorMessage != null)
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                key: const Key('passButton'),
                icon: const Icon(Icons.close),
                onPressed: _pass,
              ),
              IconButton(
                key: const Key('likeButton'),
                icon: const Icon(Icons.favorite),
                onPressed: _like,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
