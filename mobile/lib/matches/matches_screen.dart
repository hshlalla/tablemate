import 'package:flutter/material.dart';
import '../photo_url.dart';
import '../widgets/profile_avatar.dart';
import 'matches_repository.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    required this.repository,
    required this.onSelectMatch,
    this.imageBaseUrl = '',
  });

  final MatchesRepository repository;
  final void Function(
    String matchId,
    String counterpartName,
    String? counterpartPhotoUrl,
  ) onSelectMatch;
  final String imageBaseUrl;

  @override
  State<MatchesScreen> createState() => MatchesScreenState();
}

class MatchesScreenState extends State<MatchesScreen> {
  List<Map<String, dynamic>> _matches = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Re-fetches the matches list. Exposed so callers holding a
  /// `GlobalKey<MatchesScreenState>` (e.g. HomeScreen on tab activation, or
  /// a retry button after a failed load) can trigger a refresh.
  Future<void> refresh() => _load();

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ElevatedButton(
                key: const Key('retryButton'),
                onPressed: refresh,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: ListView.builder(
        itemCount: _matches.length,
        itemBuilder: (context, index) {
          final match = _matches[index];
          final matchId = match['id'] as String;
          final name = match['counterpartName'] as String? ?? '(이름 없음)';
          final photoUrl = absolutePhotoUrl(
            widget.imageBaseUrl,
            match['counterpartPhotoUrl'] as String?,
          );
          return ListTile(
            leading: ProfileAvatar(imageUrl: photoUrl),
            title: Text(name),
            onTap: () => widget.onSelectMatch(matchId, name, photoUrl),
          );
        },
      ),
    );
  }
}
