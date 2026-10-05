import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

/// CUSTOMER app: while a request is accepted / in progress, writes the
/// customer's live position to `service_requests/{id}.customerLocation`
/// so the provider can follow them. Call start() when the request is
/// accepted and stop() when it ends (or in dispose()).
class CustomerLocationSharer {
  StreamSubscription<Position>? _sub;
  String? _requestId;

  bool get isRunning => _sub != null;

  Future<void> start(String requestId) async {
    if (_requestId == requestId && _sub != null) return;
    await stop();

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _requestId = requestId;
    var lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      final now = DateTime.now();
      if (now.difference(lastWrite) < const Duration(seconds: 5)) return;
      lastWrite = now;
      FirebaseFirestore.instance
          .collection('service_requests')
          .doc(requestId)
          .update({
            'customerLocation': {
              'latitude': pos.latitude,
              'longitude': pos.longitude,
            },
          })
          .catchError((_) {});
    }, onError: (_) {});
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _requestId = null;
  }
}
