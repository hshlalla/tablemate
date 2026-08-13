import 'package:flutter/material.dart';
import 'auth_repository.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;

  Future<void> _submit() async {
    try {
      await widget.authRepository.signup(_emailController.text, _passwordController.text);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
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
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              key: const Key('signupButton'),
              onPressed: _submit,
              child: const Text('Sign up'),
            ),
          ],
        ),
      ),
    );
  }
}
