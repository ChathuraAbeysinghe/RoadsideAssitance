import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Keeps the assistance provider's `currentLocation` in Firestore up to date,
/// including while the app is in the background.
///
///  - Android: runs as a foreground service (shows an ongoing notification),
///    which is what keeps location updates alive when the app is minimised.
///  - iOS: uses background location updates (shows the blue status pill).
///
/// Usage:
///   // once, in main(), after Firebase.initializeApp():
///   ProviderLocationService.instance.autoManage();
///
/// After that it runs on its own, whatever page is open: it starts when an
/// available assistance provider is logged in and stops on logout. Call
/// `refresh()` right after you change `isAvailable` in Firestore.
class ProviderLocationService {
  ProviderLocationService._();
  static final ProviderLocationService instance = ProviderLocationService._();

  /// Don't write to Firestore more often than this, even if the GPS fires
  /// faster. Keeps your write count (and bill) under control.
  static const Duration _minWriteGap = Duration(seconds: 5);

  StreamSubscription<Position>? _sub;
  String? _uid;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  bool _starting = false;
  StreamSubscription<User?>? _authSub;

  bool get isRunning => _sub != null;

  /// Call once at app start. Follows the login state by itself.
  void autoManage() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        stop();
      } else {
        refresh();
      }
    });
  }

  /// Re-checks the logged-in user and starts/stops sharing to match:
  /// sharing runs only for an assistance provider with `isAvailable == true`.
  /// Call this after the provider toggles availability.
  Future<void> refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await stop();
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final isProvider = data?['userType'] == 'assistanceProvider';
      final available = data?['isAvailable'] as bool? ?? true;
      if (isProvider && available) {
        await start(user.uid);
      } else {
        await stop();
      }
    } catch (_) {}
  }

  /// Starts sharing. Returns false if location is off or permission was
  /// refused (the caller can show an alert in that case).
  Future<bool> start(String uid) async {
    if (_sub != null && _uid == uid) return true;
    if (_starting) return false;
    _starting = true;
    try {
      await stop();

      if (!await Geolocator.isLocationServiceEnabled()) return false;
      if (!await _ensurePermission()) return false;

      _uid = uid;
      _sub = Geolocator.getPositionStream(locationSettings: _settings())
          .listen(_onPosition, onError: (_) {});

      // Write one position straight away so customers see this provider
      // without waiting for the first movement.
      try {
        _onPosition(await Geolocator.getCurrentPosition(), force: true);
      } catch (_) {}
      return true;
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _uid = null;
  }

  // ---------------- internals ----------------
  Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  LocationSettings _settings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // metres moved before a new update
          intervalDuration: const Duration(seconds: 10),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'You are online',
            notificationText: 'Sharing your location with nearby customers',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 10,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        );
    }
  }

  void _onPosition(Position pos, {bool force = false}) {
    final uid = _uid;
    if (uid == null) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastWrite) < _minWriteGap) return;
    _lastWrite = now;

    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({
          'currentLocation': {
            'latitude': pos.latitude,
            'longitude': pos.longitude,
          },
          'heading': pos.heading,
          // Lets customers' apps ignore providers that went silent.
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        })
        .catchError((_) {});
  }
}
