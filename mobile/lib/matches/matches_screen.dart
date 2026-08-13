import 'package:flutter/material.dart';
import 'matches_repository.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    required this.repository,
    required this.onSelectMatch,
  });

  final MatchesRepository repository;
  final void Function(String matchId) onSelectMatch;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  List<Map<String, dynamic>> _matches = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final matches = await widget.repository.listMatches();
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    return Scaffold(
      body: ListView.builder(
        itemCount: _matches.length,
        itemBuilder: (context, index) {
          final matchId = _matches[index]['id'] as String;
          return ListTile(
            title: Text(matchId),
            onTap: () => widget.onSelectMatch(matchId),
          );
        },
      ),
    );
  }
}
