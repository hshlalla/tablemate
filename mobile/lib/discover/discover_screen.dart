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

  Future<void> _like() async {
    final matched = await widget.repository.swipe(widget.candidateUserId, true);
    setState(() => _matched = matched);
  }

  Future<void> _pass() async {
    await widget.repository.swipe(widget.candidateUserId, false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: SwipeCard(name: widget.candidateName)),
          if (_matched == true) const Text("It's a match!"),
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
