import 'package:flutter/material.dart';

class GatekeeperScreen extends StatefulWidget {
  const GatekeeperScreen({super.key});

  @override
  State<GatekeeperScreen> createState() => _GatekeeperScreenState();
}

class _GatekeeperScreenState extends State<GatekeeperScreen> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isObscured = true;
  String? _errorText;

  // The requested global password
  static const String _appPassword = 'AYTF&87eBwiuvw';

  Future<void> _verifyPassword() async {
    if (_passwordController.text == _appPassword) {
      if (mounted) {
        // Navigate directly to Home, bypassing Auth
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else {
      setState(() {
        _errorText = 'Incorrect password';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(32),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 64, color: Colors.deepPurple),
                  const SizedBox(height: 16),
                  Text(
                    'App Locked',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Please enter the access code to continue.'),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _passwordController,
                    obscureText: _isObscured,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      errorText: _errorText,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_isObscured ? Icons.visibility : Icons.visibility_off),
                        onPressed: () {
                          setState(() {
                            _isObscured = !_isObscured;
                          });
                        },
                      ),
                    ),
                    onSubmitted: (_) => _verifyPassword(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _verifyPassword,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Unlock'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
