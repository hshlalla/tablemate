import 'package:flutter/material.dart';
import 'matches_repository.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key, required this.repository});

  final MatchesRepository repository;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  List<Map<String, dynamic>> _matches = [];

  @override
  void initState() {
    super.initState();
    widget.repository.listMatches().then((matches) => setState(() => _matches = matches));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: _matches.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(_matches[index]['id'] as String),
        ),
      ),
    );
  }
}
