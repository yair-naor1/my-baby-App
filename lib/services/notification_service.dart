import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../data/repositories/book_repository.dart';
import '../features/memories/memory_form_screen.dart';
import '../navigation.dart';

/// Registers this device for push notifications and handles taps on the
/// reminders `functions/notifications.js` sends (spec §7.6): monthly/yearly
/// birthday nudges and per-book inactivity nudges. Tapping one deep-links
/// straight into that book's Add Memory flow.
class NotificationService {
  final _messaging = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;
  final _bookRepository = BookRepository();

  bool _initialized = false;

  /// Call once, after a user is known to be signed in (e.g. [HomeScreen]'s
  /// `initState`). Safe to call more than once — later calls are a no-op.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final settings = await _messaging.requestPermission();

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    await _registerToken();
    _messaging.onTokenRefresh.listen(_saveToken);

    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleTap(initialMessage);
    }
  }

  Future<void> _registerToken() async {
    final token = await _messaging.getToken();
    if (token != null) {
      await _saveToken(token);
    }
  }

  Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  Future<void> _handleTap(RemoteMessage message) async {
    final bookId = message.data['bookId'];
    if (bookId == null) return;

    final book = await _bookRepository.getBook(bookId);
    if (book == null) return;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => MemoryFormScreen(
          bookId: book.bookId,
          childGender: book.childGender,
        ),
      ),
    );
  }
}
