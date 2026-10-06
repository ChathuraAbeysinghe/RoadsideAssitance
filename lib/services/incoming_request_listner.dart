import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../entities/app_user.dart';
import '../entities/service_request.dart';

/// Give this to `MaterialApp(navigatorKey: appNavigatorKey)` so the listener
/// below can open a page from anywhere, whatever screen the provider is on.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Runs for the whole life of the app. While an available assistance provider
/// is logged in, it watches for new pending requests that are:
///   - for a service the provider offers,
///   - inside the request's current search radius from the provider, and
///   - not expired / not one the provider already saw.
/// When one arrives it opens the "incoming request" page on top of whatever
/// page is showing. If the provider accepts, it then opens the job page
/// (map + status buttons).
///
/// Setup (once, in main(), after Firebase.initializeApp()):
///   IncomingRequestListener.instance.autoManage(
///     navigatorKey: appNavigatorKey,
///     pageBuilder: (request) => IncomingRequestPage(request: request),
///     acceptedPageBuilder: (request) => ProviderJobPage(request: request),
///   );
///
/// Call `refresh()` after the provider changes availability or services.
class IncomingRequestListener {
  IncomingRequestListener._();
  static final IncomingRequestListener instance = IncomingRequestListener._();

  GlobalKey<NavigatorState>? _navKey;
  Widget Function(ServiceRequest)? _pageBuilder;
  Widget Function(ServiceRequest)? _acceptedPageBuilder;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<ServiceRequest>>? _reqSub;

  String? _uid;
  GeoLocation _savedLocation = const GeoLocation(latitude: 0, longitude: 0);

  /// Requests already shown (key = id + expiry, so a renewed request is
  /// offered again, but the same one isn't shown twice).
  final Set<String> _handled = {};
  List<ServiceRequest> _latest = const [];
  bool _busy = false; // evaluating, or a page is open

  void _log(String msg) => debugPrint('[IncomingRequest] $msg');

  void autoManage({
    required GlobalKey<NavigatorState> navigatorKey,
    required Widget Function(ServiceRequest) pageBuilder,
    Widget Function(ServiceRequest)? acceptedPageBuilder,
  }) {
    _navKey = navigatorKey;
    _pageBuilder = pageBuilder;
    _acceptedPageBuilder = acceptedPageBuilder;
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _stop();
      } else {
        refresh();
      }
    });
  }

  /// Re-checks the logged-in user: listening only runs for an available
  /// assistance provider that offers at least one service.
  Future<void> refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _stop();
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data == null) {
        _stop();
        return;
      }
      final appUser = userFromMap(user.uid, data);
      if (appUser is AssistanceProvider &&
          appUser.isAvailable &&
          appUser.services.isNotEmpty) {
        _savedLocation = appUser.currentLocation;
        _start(user.uid, appUser.services);
      } else {
        _log('not an available provider, not listening');
        _stop();
      }
    } catch (e) {
      _log('refresh() failed: $e');
    }
  }

  void _start(String uid, Set<ServiceType> services) {
    _reqSub?.cancel();
    _uid = uid;
    _log('listening for ${services.map((s) => s.name).join(', ')}');
    _reqSub = watchPendingRequests(services)
        .listen(_onRequests, onError: (e) => _log('request stream error: $e'));
  }

  void _stop() {
    _reqSub?.cancel();
    _reqSub = null;
    _uid = null;
    _latest = const [];
  }

  // ---------------- handling ----------------
  String _key(ServiceRequest r) =>
      '${r.id}_${r.expiresAt.millisecondsSinceEpoch}';

  void _onRequests(List<ServiceRequest> list) {
    _latest = list;
    _drain();
  }

  /// Shows pending requests one at a time. While a page is open new ones
  /// wait; when it closes we look at the latest list again.
  Future<void> _drain() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_uid != null) {
        ServiceRequest? next;
        for (final r in _candidates()) {
          if (await _isNearby(r)) {
            next = r;
            break;
          }
        }
        if (next == null) break;

        _handled.add(_key(next));
        final shown = await _show(next);
        if (!shown) {
          _handled.remove(_key(next)); // app not ready; retry later
          break;
        }
      }
    } finally {
      _busy = false;
    }
  }

  List<ServiceRequest> _candidates() {
    final now = DateTime.now();
    final list = _latest.where((r) {
      return r.status == RequestStatus.pending &&
          r.expiresAt.isAfter(now) &&
          r.customerUid != _uid && // never offer a provider their own request
          !_handled.contains(_key(r));
    }).toList();
    list.sort((a, b) => (a.createdAt ?? now).compareTo(b.createdAt ?? now));
    return list;
  }

  Future<bool> _isNearby(ServiceRequest r) async {
    final me = await _myPosition();
    if (me == null) {
      _log('no position for this provider yet, skipping ${r.id}');
      return false;
    }
    final km = const Distance().as(
      LengthUnit.Kilometer,
      me,
      LatLng(r.pickup.latitude, r.pickup.longitude),
    );
    final ok = km <= r.searchRadiusKm;
    _log(
      'request ${r.id}: ${km.toStringAsFixed(1)} km away, '
      'radius ${r.searchRadiusKm} km -> ${ok ? 'show' : 'wait'}',
    );
    return ok;
  }

  Future<LatLng?> _myPosition() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      return LatLng(p.latitude, p.longitude);
    } catch (_) {}
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p != null) return LatLng(p.latitude, p.longitude);
    } catch (_) {}
    if (_savedLocation.latitude != 0 || _savedLocation.longitude != 0) {
      return LatLng(_savedLocation.latitude, _savedLocation.longitude);
    }
    return null;
  }

  /// Opens the incoming request page and waits until the provider closes it.
  /// If they accepted, opens the job page and waits for that too, so no new
  /// request pops up over a job in progress.
  Future<bool> _show(ServiceRequest r) async {
    final nav = _navKey?.currentState;
    final builder = _pageBuilder;
    if (nav == null || builder == null) return false;
    _log('showing request ${r.id}');

    final accepted = await nav.push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => builder(r)),
    );

    final jobBuilder = _acceptedPageBuilder;
    if (accepted == true && jobBuilder != null && nav.mounted) {
      _log('accepted ${r.id}, opening job page');
      await nav.push<void>(MaterialPageRoute(builder: (_) => jobBuilder(r)));
    }
    return true;
  }
}
