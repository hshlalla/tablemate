import 'package:flutter/material.dart';
import '../app_session.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final AppSession session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  String? _infoMessage;

  Future<void> _submit() async {
    try {
      await widget.session.login(_emailController.text, _passwordController.text);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _infoMessage = null;
      });
    }
  }

  Future<void> _goToSignup() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SignupScreen(authRepository: widget.session.authRepository),
      ),
    );
    if (result == true && mounted) {
      setState(() {
        _infoMessage = '가입 완료 — 로그인해주세요';
        _errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              key: const Key('emailField'),
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              key: const Key('passwordField'),
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            if (_infoMessage != null)
              Text(_infoMessage!, style: const TextStyle(color: Colors.green)),
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              key: const Key('loginButton'),
              onPressed: _submit,
              child: const Text('Log in'),
            ),
            TextButton(
              key: const Key('goToSignupButton'),
              onPressed: _goToSignup,
              child: const Text('회원가입'),
            ),
          ],
        ),
      ),
    );
  }
}
