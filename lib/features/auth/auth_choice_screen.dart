import 'package:flutter/material.dart';

import '../../data/repositories/auth_repository.dart';
import '../../utils/error_messages.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class AuthChoiceScreen extends StatefulWidget {
  const AuthChoiceScreen({super.key});

  @override
  State<AuthChoiceScreen> createState() => _AuthChoiceScreenState();
}

class _AuthChoiceScreenState extends State<AuthChoiceScreen> {
  final _authRepository = AuthRepository();
  bool _isSigningInWithGoogle = false;
  String? _errorMessage;

  Future<void> _continueWithGoogle() async {
    setState(() {
      _isSigningInWithGoogle = true;
      _errorMessage = null;
    });

    try {
      await _authRepository.signInWithGoogle();
      // AuthGate's authStateChanges() listener takes it from here.
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = friendlyErrorMessage(
          e,
          fallback: 'Could not sign in with Google. Please try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSigningInWithGoogle = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Baby Book',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 260,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _isSigningInWithGoogle ? null : _continueWithGoogle,
                  icon: _isSigningInWithGoogle
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.g_mobiledata, size: 28),
                  label: const Text('Continue with Google'),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 220,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  child: const Text('Log In'),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: 220,
                height: 50,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                    );
                  },
                  child: const Text('Create Account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
