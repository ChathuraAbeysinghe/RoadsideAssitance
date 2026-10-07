import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../entities/service_request.dart';

/// CUSTOMER (driver) app: while a request is accepted / in progress, writes
/// the user's live position to
///   - `service_requests/{id}.customerLocation`  (so the provider can follow)
///   - `users/{uid}.currentLocation`             (the user's own location)
///
/// It keeps running when the app is in the background (Android foreground
/// service with a notification, iOS background location updates) and stops
/// by itself as soon as the request is no longer active (completed,
/// cancelled, expired), even if no page is open.
///
/// It is a singleton: `CustomerLocationSharer()` always returns the same
/// instance, so closing a page does not stop the sharing.
class CustomerLocationSharer {
  CustomerLocationSharer._();
  static final CustomerLocationSharer instance = CustomerLocationSharer._();
  factory CustomerLocationSharer() => instance;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<ServiceRequest?>? _reqSub;
  String? _requestId;
  bool _starting = false;

  bool get isRunning => _posSub != null;

  /// Location settings that keep updates coming while the app is in the
  /// background.
  LocationSettings _settings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          intervalDuration: const Duration(seconds: 5),
          // A foreground service keeps the app alive in the background and
          // shows an ongoing notification while the request is active.
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Roadside Assistance',
            notificationText: 'Sharing your location for your active request',
            notificationChannelName: 'Active request location',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
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

  Future<void> start(String requestId) async {
    if (_starting) return;
    if (_requestId == requestId && _posSub != null) return;
    _starting = true;
    try {
      await stop();

      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      _requestId = requestId;

      // Stop on our own when the request ends, whatever page is open.
      _reqSub = watchRequest(requestId).listen((r) {
        if (r != null && !kActiveStatuses.contains(r.status)) stop();
      }, onError: (_) {});

      final db = FirebaseFirestore.instance;
      var lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

      _posSub = Geolocator.getPositionStream(locationSettings: _settings())
          .listen((pos) {
            final now = DateTime.now();
            if (now.difference(lastWrite) < const Duration(seconds: 5)) return;
            lastWrite = now;

            final location = <String, dynamic>{
              'latitude': pos.latitude,
              'longitude': pos.longitude,
              // Direction of travel, only when it is meaningful.
              if (pos.heading.isFinite && pos.heading >= 0 && pos.speed > 0.5)
                'heading': pos.heading,
            };

            // Separate writes so one failing does not block the other.
            db
                .collection('service_requests')
                .doc(requestId)
                .update({'customerLocation': location})
                .catchError((_) {});

            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid != null) {
              db
                  .collection('users')
                  .doc(uid)
                  .update({'currentLocation': location})
                  .catchError((_) {});
            }
          }, onError: (_) {});
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    await _posSub?.cancel();
    await _reqSub?.cancel();
    _posSub = null;
    _reqSub = null;
    _requestId = null;
  }
}
