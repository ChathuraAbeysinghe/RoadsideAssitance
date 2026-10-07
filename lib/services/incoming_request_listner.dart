import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../entities/app_user.dart';
import '../entities/service_request.dart';
import 'tracking_registry.dart';

/// Give this to `MaterialApp(navigatorKey: appNavigatorKey)` so the listener
/// below can open pages from anywhere, whatever screen the user is on.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

typedef RequestPageBuilder = Widget Function(ServiceRequest request);

/// Runs for the whole life of the app and drives navigation for BOTH roles.
///
/// ASSISTANCE PROVIDER
///   1. While available (and offering at least one service), watches pending
///      requests inside the request's search radius and opens the incoming
///      request page on top of whatever page is showing.
///   2. On Accept, opens the provider tracking page (once).
///   3. While the provider is on a job, no new popups are shown. Waiting
///      requests are shown as soon as the job is finished.
///   4. If the provider has an active job when the app starts (or it
///      appears some other way), opens the provider tracking page for it.
///   5. Watches the provider's own user document, so going online/offline
///      or changing services starts/stops the request watch by itself.
///      No manual refresh() call is needed from any page.
///
/// DRIVER (customer)
///   - When a provider accepts the driver's request while the driver is on
///     the app (or the app starts with an active request), opens the driver
///     tracking page.
///
/// A job's tracking page is opened automatically only once per app session
/// (see [TrackingRegistry]), so leaving the page is never undone by a later
/// status change. Reopen it from the home page's ongoing requests.
///
/// Setup (once, in main(), after Firebase.initializeApp()):
///   IncomingRequestListener.instance.autoManage(
///     navigatorKey: appNavigatorKey,
///     incomingPageBuilder: (r) => IncomingRequestPage(request: r),
///     providerTrackingBuilder: (r) => ProviderTrackingPage(requestId: r.id),
///     driverTrackingBuilder: (r) => DriverTrackingPage(
///       requestId: r.id,
///       pickup: LatLng(r.pickup.latitude, r.pickup.longitude),
///     ),
///   );
class IncomingRequestListener {
  IncomingRequestListener._();
  static final IncomingRequestListener instance = IncomingRequestListener._();

  GlobalKey<NavigatorState>? _navKey;
  RequestPageBuilder? _incomingBuilder;
  RequestPageBuilder? _providerTrackingBuilder;
  RequestPageBuilder? _driverTrackingBuilder;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<List<ServiceRequest>>?
  _pendingSub; // provider: new requests
  StreamSubscription<List<ServiceRequest>>? _jobSub; // provider: own jobs
  StreamSubscription<List<ServiceRequest>>? _driverSub; // driver: own requests

  /// Logged-in user for the job / driver watches.
  String? _roleUid;

  /// Uid whose user document is being watched.
  String? _userDocUid;

  /// Last seen "availability + services" of the provider. The user document
  /// changes every few seconds (GPS), so the pending watch is only restarted
  /// when this changes.
  String _providerSig = '';

  // ---- provider: incoming requests ----
  /// Set while listening for pending requests.
  String? _uid;
  GeoLocation _savedLocation = const GeoLocation(latitude: 0, longitude: 0);

  /// Requests already shown (key = id + expiry, so a renewed request is
  /// offered again, but the same one isn't shown twice).
  final Set<String> _handled = {};
  List<ServiceRequest> _latest = const [];

  /// True while an incoming request page (or the tracking page opened by
  /// accepting it) is on screen.
  bool _busy = false;

  // ---- provider: jobs ----
  List<ServiceRequest> _latestJobs = const [];
  final Set<String> _providerOpened = {};
  bool _jobPushing = false;

  // ---- driver ----
  List<ServiceRequest> _latestDriver = const [];
  final Set<String> _driverOpened = {};
  bool _driverPushing = false;

  Timer? _retryTimer;

  void _log(String msg) => debugPrint('[IncomingRequest] $msg');

  void autoManage({
    required GlobalKey<NavigatorState> navigatorKey,
    required RequestPageBuilder incomingPageBuilder,
    required RequestPageBuilder providerTrackingBuilder,
    required RequestPageBuilder driverTrackingBuilder,
  }) {
    _navKey = navigatorKey;
    _incomingBuilder = incomingPageBuilder;
    _providerTrackingBuilder = providerTrackingBuilder;
    _driverTrackingBuilder = driverTrackingBuilder;
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _stopAll();
      } else {
        refresh();
      }
    });
  }

  /// Re-checks the logged-in user and starts/stops the right watches.
  /// Called automatically on login; pages don't need to call it.
  Future<void> refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _stopAll();
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data == null) {
        _stopAll();
        return;
      }
      _applyUser(user.uid, userFromMap(user.uid, data), force: true);
    } catch (e) {
      _log('refresh() failed: $e');
    }
  }

  /// Applies the user's current role/state to the watches.
  void _applyUser(String uid, AppUser appUser, {bool force = false}) {
    if (appUser is AssistanceProvider) {
      _stopDriverWatch();
      _startJobWatch(uid);
      _startUserWatch(uid);
      _savedLocation = appUser.currentLocation;

      final sig =
          '${appUser.isAvailable}|'
          '${(appUser.services.map((s) => s.name).toList()..sort()).join(',')}';
      if (!force && sig == _providerSig) return;
      _providerSig = sig;

      if (appUser.isAvailable && appUser.services.isNotEmpty) {
        _startPending(uid, appUser.services);
      } else {
        _log('provider not available, not listening for new requests');
        _stopPending();
      }
    } else {
      _stopUserWatch();
      _stopPending();
      _stopJobWatch();
      _startDriverWatch(uid);
    }
  }

  // ---------------- start / stop ----------------
  /// Watches the provider's own document so availability / service changes
  /// are picked up without any page calling refresh().
  void _startUserWatch(String uid) {
    if (_userSub != null && _userDocUid == uid) return;
    _userSub?.cancel();
    _userDocUid = uid;
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
          final data = snap.data();
          if (data == null) return;
          try {
            _applyUser(uid, userFromMap(uid, data));
          } catch (e) {
            _log('user doc parse failed: $e');
          }
        }, onError: (e) => _log('user stream error: $e'));
  }

  void _stopUserWatch() {
    _userSub?.cancel();
    _userSub = null;
    _userDocUid = null;
    _providerSig = '';
  }

  void _startPending(String uid, Set<ServiceType> services) {
    _pendingSub?.cancel();
    _uid = uid;
    _log('listening for ${services.map((s) => s.name).join(', ')}');
    _pendingSub = watchPendingRequests(services)
        .listen(_onPending, onError: (e) => _log('pending stream error: $e'));
  }

  void _stopPending() {
    _pendingSub?.cancel();
    _pendingSub = null;
    _uid = null;
    _latest = const [];
  }

  void _startJobWatch(String uid) {
    if (_jobSub != null && _roleUid == uid) return;
    _jobSub?.cancel();
    _roleUid = uid;
    _jobSub = watchProviderJobs(uid).listen((list) {
      _latestJobs = list;
      _openProviderJobs();
      // A finished job frees the provider: show any request that waited.
      _drain();
    }, onError: (e) => _log('job stream error: $e'));
  }

  void _stopJobWatch() {
    _jobSub?.cancel();
    _jobSub = null;
    _latestJobs = const [];
  }

  void _startDriverWatch(String uid) {
    if (_driverSub != null && _roleUid == uid) return;
    _driverSub?.cancel();
    _roleUid = uid;
    _driverSub = FirebaseFirestore.instance
        .collection('service_requests')
        .where('customerUid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final list = <ServiceRequest>[];
          for (final d in snap.docs) {
            try {
              list.add(ServiceRequest.fromMap(d.id, d.data()));
            } catch (_) {}
          }
          return list;
        })
        .listen((list) {
          _latestDriver = list;
          _openDriverPages();
        }, onError: (e) => _log('driver stream error: $e'));
  }

  void _stopDriverWatch() {
    _driverSub?.cancel();
    _driverSub = null;
    _latestDriver = const [];
  }

  void _stopAll() {
    _stopPending();
    _stopJobWatch();
    _stopDriverWatch();
    _stopUserWatch();
    _roleUid = null;
    _handled.clear();
    _providerOpened.clear();
    _driverOpened.clear();
    _retryTimer?.cancel();
    TrackingRegistry.clear();
  }

  // ---------------- provider: incoming requests ----------------
  String _key(ServiceRequest r) =>
      '${r.id}_${r.expiresAt.millisecondsSinceEpoch}';

  void _onPending(List<ServiceRequest> list) {
    _latest = list;
    _drain();
  }

  /// True while the provider has a job in progress.
  bool get _onJob => _latestJobs.any((j) => kActiveStatuses.contains(j.status));

  /// Shows pending requests one at a time. While a page is open new ones
  /// wait; when it closes we look at the latest list again.
  Future<void> _drain() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_uid != null) {
        // Never interrupt a provider who is already on a job. This runs
        // again when the job stream reports the job as finished.
        if (_onJob) break;

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
          _retryLater();
          break;
        }
      }
    } finally {
      _busy = false;
      // A job may have appeared while we were busy.
      _openProviderJobs();
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
    LatLng? me;
    if (_uid != null) {
      try {
        final psSnap = await FirebaseFirestore.instance
            .collection('providerServices')
            .where('providerUid', isEqualTo: _uid)
            .where('serviceType', isEqualTo: r.serviceType.name)
            .where('isActive', isEqualTo: true)
            .get();
        if (psSnap.docs.isNotEmpty) {
          final locMap =
              psSnap.docs.first.data()['locationGeo'] as Map<String, dynamic>?;
          if (locMap != null) {
            final lat = locMap['latitude'];
            final lng = locMap['longitude'];
            if (lat != null && lng != null && (lat != 0 || lng != 0)) {
              me = LatLng((lat as num).toDouble(), (lng as num).toDouble());
            }
          }
        }
      } catch (_) {}
    }

    me ??= await _myPosition();

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

  /// Opens the incoming request page on top of whatever is showing and waits
  /// until it closes. If the provider accepted, opens the tracking page once.
  /// Returns false only if the app's navigator isn't ready yet.
  Future<bool> _show(ServiceRequest r) async {
    final nav = _navKey?.currentState;
    final builder = _incomingBuilder;
    if (nav == null || builder == null || !nav.mounted) return false;

    final accepted = await nav.push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => builder(r)),
    );

    if (accepted == true) {
      // Stops _openProviderJobs from opening a second tracking page.
      _providerOpened.add(r.id);
      await _pushPage(_providerTrackingBuilder, r);
    }
    return true;
  }

  // ---------------- provider: own jobs ----------------
  ServiceRequest? _nextProviderJob() {
    for (final r in _latestJobs) {
      if (kActiveStatuses.contains(r.status) &&
          !_providerOpened.contains(r.id) &&
          !TrackingRegistry.wasOpened(r.id)) {
        return r;
      }
    }
    return null;
  }

  /// Opens the tracking page for an active job the provider hasn't seen yet
  /// this session (e.g. the app was restarted mid-job). Skipped while the
  /// accept flow is running; it opens the page itself.
  Future<void> _openProviderJobs() async {
    if (_jobPushing || _busy) return;
    _jobPushing = true;
    try {
      while (_roleUid != null && _jobSub != null && !_busy) {
        final next = _nextProviderJob();
        if (next == null) break;

        _providerOpened.add(next.id);
        final ok = await _pushPage(_providerTrackingBuilder, next);
        if (!ok) {
          _providerOpened.remove(next.id);
          _retryLater();
          break;
        }
      }
    } finally {
      _jobPushing = false;
    }
  }

  // ---------------- driver ----------------
  ServiceRequest? _nextDriverRequest() {
    for (final r in _latestDriver) {
      if (kActiveStatuses.contains(r.status) &&
          r.providerUid != null &&
          !_driverOpened.contains(r.id) &&
          !TrackingRegistry.wasOpened(r.id)) {
        return r;
      }
    }
    return null;
  }

  /// Opens the driver tracking page once a provider has accepted the
  /// driver's request.
  Future<void> _openDriverPages() async {
    if (_driverPushing) return;
    _driverPushing = true;
    try {
      while (_roleUid != null && _driverSub != null) {
        final first = _nextDriverRequest();
        if (first == null) break;

        // Short grace period: the searching page may open the tracking page
        // itself. If it does, the registry knows and we skip.
        await Future.delayed(const Duration(milliseconds: 700));
        if (_driverSub == null) break;

        final next = _nextDriverRequest();
        if (next == null) break;

        _driverOpened.add(next.id);
        _log('provider accepted ${next.id}, opening driver tracking page');
        final ok = await _pushPage(_driverTrackingBuilder, next);
        if (!ok) {
          _driverOpened.remove(next.id);
          _retryLater();
          break;
        }
      }
    } finally {
      _driverPushing = false;
    }
  }

  // ---------------- shared ----------------
  /// Pushes a page and waits until it closes. Returns false if the app's
  /// navigator isn't ready yet.
  Future<bool> _pushPage(RequestPageBuilder? builder, ServiceRequest r) async {
    final nav = _navKey?.currentState;
    if (nav == null || builder == null || !nav.mounted) return false;
    await nav.push<void>(MaterialPageRoute(builder: (_) => builder(r)));
    return true;
  }

  /// Tries again shortly (e.g. the navigator wasn't ready at app start).
  void _retryLater() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () {
      _drain();
      _openProviderJobs();
      _openDriverPages();
    });
  }
}
