import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';

/// Must be a top-level function. Runs when a push arrives while the app is
/// in the background or closed. The system shows the notification itself
/// (the Cloud Function sends a `notification` payload), so nothing else is
/// needed here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Saves this device's FCM token on the user's document so the Cloud Function
/// can push "new request" notifications while the app is closed.
///
/// Setup (main.dart, after Firebase.initializeApp()):
///   FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
///   await PushNotificationService.instance.init();
///
/// Before signing out:
///   await PushNotificationService.instance.removeToken();
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  /// Must match `channelId` in the Cloud Function.
  static const _channel = AndroidNotificationChannel(
    'incoming_requests',
    'Incoming requests',
    description: 'New roadside assistance requests near you',
    importance: Importance.max,
    playSound: true,
  );

  bool _started = false;
  String? _token;

  void _log(String msg) => debugPrint('[Push] $msg');

  Future<void> init() async {
    if (_started) return;
    _started = true;

    final messaging = FirebaseMessaging.instance;

    // Android 13+ and iOS ask the user for permission here.
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // High-importance channel so the notification pops up (heads-up).
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    // Save the token for whoever is signed in (now and after future logins).
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) _saveToken(user.uid);
    });
    messaging.onTokenRefresh.listen((token) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) _saveToken(user.uid, token);
    });
  }

  Future<void> _saveToken(String uid, [String? fresh]) async {
    try {
      final token = fresh ?? await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      _token = token;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
      _log('token saved for $uid: ${token.substring(0, 12)}...');
    } catch (e) {
      _log('saving token failed: $e');
    }
  }

  /// Call BEFORE FirebaseAuth.instance.signOut(), so a signed-out device
  /// stops receiving this user's notifications.
  Future<void> removeToken() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = _token ?? await FirebaseMessaging.instance.getToken();
    if (user == null || token == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmTokens': FieldValue.arrayRemove([token]),
      }, SetOptions(merge: true));
    } catch (e) {
      _log('removing token failed: $e');
    }
  }
}
