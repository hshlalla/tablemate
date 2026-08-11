import 'package:flutter/material.dart';
import 'discover_repository.dart';
import 'swipe_card.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.repository});

  final DiscoverRepository repository;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<Map<String, dynamic>> _candidates = [];
  int _index = 0;
  bool _loading = true;
  bool _swiping = false;
  bool? _matched;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    try {
      final candidates = await widget.repository.fetchCandidates();
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _index = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _current =>
      _index < _candidates.length ? _candidates[_index] : null;

  Future<void> _like() async {
    final candidate = _current;
    if (candidate == null || _swiping) return;
    setState(() => _swiping = true);
    try {
      final matched =
          await widget.repository.swipe(candidate['userId'] as String, true);
      if (!mounted) return;
      setState(() {
        _matched = matched;
        _errorMessage = null;
        _index++;
        _swiping = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _swiping = false;
      });
    }
  }

  Future<void> _pass() async {
    final candidate = _current;
    if (candidate == null || _swiping) return;
    setState(() => _swiping = true);
    try {
      await widget.repository.swipe(candidate['userId'] as String, false);
      if (!mounted) return;
      setState(() {
        _matched = null;
        _errorMessage = null;
        _index++;
        _swiping = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _swiping = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final candidate = _current;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: candidate == null
                ? const Center(child: Text('더 이상 후보가 없습니다'))
                : SwipeCard(name: candidate['displayName'] as String? ?? '(이름 없음)'),
          ),
          if (_matched == true) const Text("It's a match!"),
          if (_errorMessage != null)
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          if (candidate != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  key: const Key('passButton'),
                  icon: const Icon(Icons.close),
                  onPressed: _swiping ? null : _pass,
                ),
                IconButton(
                  key: const Key('likeButton'),
                  icon: const Icon(Icons.favorite),
                  onPressed: _swiping ? null : _like,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
