import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_session.dart';
import 'chat/chat_screen.dart';
import 'discover/discover_screen.dart';
import 'matches/matches_screen.dart';
import 'profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  final _matchesKey = GlobalKey<MatchesScreenState>();

  void _openChat(
    String matchId,
    String counterpartName,
    String? counterpartPhotoUrl,
  ) {
    final session = context.read<AppSession>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          socketClient: session.buildChatSocketClient(),
          matchId: matchId,
          counterpartName: counterpartName,
          counterpartPhotoUrl: counterpartPhotoUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_tabIndex == 0 ? 'Discover' : 'Matches'),
        actions: [
          IconButton(
            key: const Key('profileButton'),
            icon: const Icon(Icons.person),
            onPressed: () {
              final session = context.read<AppSession>();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    repository: session.profileRepository,
                    imageBaseUrl: session.baseUrl,
                  ),
                ),
              );
            },
          ),
          IconButton(
            key: const Key('logoutButton'),
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AppSession>().logout(),
          ),
        ],
      ),
      // IndexedStack keeps both tabs mounted so switching tabs doesn't reset
      // DiscoverScreen's fetched candidate queue or MatchesScreen's list.
      body: IndexedStack(
        index: _tabIndex,
        children: [
          DiscoverScreen(
            repository: session.discoverRepository,
            imageBaseUrl: session.baseUrl,
          ),
          MatchesScreen(
            key: _matchesKey,
            repository: session.matchesRepository,
            onSelectMatch: _openChat,
            imageBaseUrl: session.baseUrl,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (index) {
          if (index == 1 && index != _tabIndex) {
            _matchesKey.currentState?.refresh();
          }
          setState(() => _tabIndex = index);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Discover'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Matches'),
        ],
      ),
    );
  }
}
