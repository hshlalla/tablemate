import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_session.dart';
import 'auth_gate.dart';

const String kApiBaseUrl = 'http://localhost:3000';

void main() {
  runApp(const TableMateApp());
}

class TableMateApp extends StatelessWidget {
  const TableMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppSession(baseUrl: kApiBaseUrl)..restore(),
      child: MaterialApp(
        title: 'TableMate',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const AuthGate(),
      ),
    );
  }
}
