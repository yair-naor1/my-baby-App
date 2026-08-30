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
    } on GoogleAccountConflict catch (conflict) {
      await _resolveAccountConflict(conflict);
    } catch (e, stack) {
      // TEMP diagnostic — remove once #4 is confirmed fixed.
      debugPrint('[auth-diagnostic] ${e.runtimeType}: $e');
      debugPrint('[auth-diagnostic] $stack');

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

  /// [conflict.email] already has a Baby Book account signed in with a
  /// password — the Google sign-in itself already succeeded, so rather than
  /// just reporting failure, ask for that password right here and link the
  /// two so this account works with either method going forward.
  Future<void> _resolveAccountConflict(GoogleAccountConflict conflict) async {
    if (!mounted) return;

    final password = await showDialog<String>(
      context: context,
      builder: (context) => _PasswordPromptDialog(email: conflict.email),
    );

    if (password == null || password.isEmpty) return;

    if (mounted) {
      setState(() {
        _isSigningInWithGoogle = true;
        _errorMessage = null;
      });
    }

    try {
      await _authRepository.resolveGoogleAccountConflict(
        conflict: conflict,
        password: password,
      );
      // AuthGate's authStateChanges() listener takes it from here.
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = friendlyErrorMessage(
          e,
          fallback: 'Could not verify that password. Please try again.',
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

/// Asks for the password of an existing email/password account so its
/// Google sign-in attempt can be linked to it. Returns the entered password,
/// or null if cancelled.
class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog({required this.email});

  final String email;

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm your password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.email} already has a Baby Book account. Enter its '
            'password once to connect Google sign-in to it.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _passwordController.text),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
