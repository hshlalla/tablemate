import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_session.dart';
import 'chat/chat_screen.dart';
import 'discover/discover_screen.dart';
import 'matches/matches_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  void _openChat(String matchId) {
    final session = context.read<AppSession>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          socketClient: session.buildChatSocketClient(),
          matchId: matchId,
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
          DiscoverScreen(repository: session.discoverRepository),
          MatchesScreen(
            repository: session.matchesRepository,
            onSelectMatch: _openChat,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (index) => setState(() => _tabIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Discover'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Matches'),
        ],
      ),
    );
  }
}
