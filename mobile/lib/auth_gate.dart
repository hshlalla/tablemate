import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_session.dart';
import 'auth/login_screen.dart';
import 'home_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    if (session.isRestoring) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return session.isAuthenticated
        ? const HomeScreen()
        : LoginScreen(session: context.read<AppSession>());
  }
}
