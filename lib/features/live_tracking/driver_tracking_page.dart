import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../entities/app_user.dart';
import '../../entities/service_request.dart';
import '../../entities/vehicle.dart';
import '../../services/customer_location_sharer.dart';
import '../../services/tracking_registry.dart';

const Color _brandRed = Color(0xFFE30613);
const Color _success = Color(0xFF22C55E);
const Color _pickupBlue = Color(0xFF1E88E5);

/// Top-down vehicle image.
const String _providerVehicleIcon = 'assets/images/top-vehicle.png';

/// Which way the image itself points, in degrees clockwise from "up":
/// 0 = front of the vehicle faces the top of the image, 90 = faces right,
/// 180 = faces down, 270 = faces left. Change this if the icon turns the
/// wrong way relative to the direction of travel.
const double _vehicleIconFacing = 0;

/// Contact button icons (add both files to pubspec.yaml assets).
const String _messageIcon = 'assets/images/message.png';
const String _callIcon = 'assets/images/call.png';
const String _appPackageName = 'com.example.roadside_assitance';
const String _userAgent = 'RoadsideAssistance/1.0 (kavidupurnamal@gmail.com)';

/// Time the driver sees counting down next to "Cancel Request".
const Duration _cancelWindow = Duration(minutes: 5);

/// Padding used when fitting the route. The map is laid out 30px taller
/// than what's visible (it extends under the sheet), hence the larger bottom.
const EdgeInsets _fitPadding = EdgeInsets.fromLTRB(50, 90, 50, 70);

class _RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  const _RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

/// OSRM public demo server (testing only, same as the request page).
Future<_RouteResult?> _fetchRoute(LatLng a, LatLng b) async {
  try {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${a.longitude},${a.latitude};${b.longitude},${b.latitude}'
      '?overview=full&geometries=geojson',
    );
    final res = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;
    final first = routes[0] as Map<String, dynamic>;
    final coords = first['geometry']['coordinates'] as List;
    return _RouteResult(
      points: coords
          .map(
            (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          )
          .toList(),
      distanceMeters: (first['distance'] as num).toDouble(),
      durationSeconds: (first['duration'] as num).toDouble(),
    );
  } catch (_) {
    return null;
  }
}

/// DRIVER-side tracking page. Shown to the driver (the customer) once an
/// assistance provider accepts their request. Live map with the provider's
/// position, the road route to the driver's pickup point and the provider's
/// details. Follows the request status all the way to completed/cancelled.
///
/// Opened automatically by IncomingRequestListener while the driver is on
/// the app, and can also be opened from the home page (ongoing requests).
class DriverTrackingPage extends StatefulWidget {
  final String requestId;
  final LatLng pickup;

  const DriverTrackingPage({
    super.key,
    required this.requestId,
    required this.pickup,
  });

  @override
  State<DriverTrackingPage> createState() => _DriverTrackingPageState();
}

class _DriverTrackingPageState extends State<DriverTrackingPage> {
  final _mapController = MapController();
  final _sharer = CustomerLocationSharer();

  StreamSubscription<ServiceRequest?>? _reqSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _provSub;
  Timer? _recenterTimer;
  Timer? _cancelTimer;

  ServiceRequest? _request;
  AppUser? _provider;
  LatLng? _providerLoc;
  // Direction the provider is heading, degrees clockwise from north.
  // [_providerTurns] is the unwrapped (continuous) version used for animation
  // so the icon always turns the short way round.
  double _providerHeading = 0;
  double _providerTurns = 0;
  Vehicle? _providerVehicle;
  bool _vehicleRequested = false;

  // Road route provider -> pickup
  List<LatLng> _routePoints = [];
  double? _routeKm;
  int? _routeMin;
  bool _routing = false;
  LatLng? _routeOrigin;
  DateTime _lastRouteAt = DateTime.fromMillisecondsSinceEpoch(0);

  Duration _cancelRemaining = _cancelWindow;
  bool _cancelTimerStarted = false;

  // Live GPS of this user (blue dot), used once the service is in progress.
  LatLng? _userLoc;
  double? _heading; // degrees clockwise from north; last known while moving
  StreamSubscription<Position>? _posSub;

  bool _mapReady = false;
  bool _sharing = false;
  DateTime _lastGesture = DateTime.fromMillisecondsSinceEpoch(0);

  RequestStatus get _status => _request?.status ?? RequestStatus.accepted;

  bool get _finished =>
      _status == RequestStatus.completed ||
      _status == RequestStatus.cancelled ||
      _status == RequestStatus.expired;

  /// Tow truck job that is under way: the route now goes to the drop-off.
  bool get _toDropoff =>
      _status == RequestStatus.inProgress && _dropoff != null;

  /// Drop-off point of the request (tow truck only), or null.
  LatLng? get _dropoff => _dropoffOf(_request);

  /// Where the route currently leads to.
  LatLng get _routeTarget => _toDropoff ? _dropoff! : widget.pickup;

  /// Where the route currently starts from. While towing it starts at this
  /// user's live GPS position (falling back to the truck's position).
  LatLng? get _routeFrom =>
      _toDropoff ? (_userLoc ?? _providerLoc) : _providerLoc;

  bool get _routeRelevant =>
      _status == RequestStatus.accepted ||
      _status == RequestStatus.onTheWay ||
      _toDropoff;

  /// Reads the drop-off from the request. Kept in one place because it
  /// depends on how ServiceRequest names/stores it; adjust here if needed.
  static LatLng? _dropoffOf(ServiceRequest? r) {
    if (r == null) return null;
    try {
      final d = (r as dynamic).dropoff;
      if (d == null) return null;
      final lat = (d.latitude as num).toDouble();
      final lng = (d.longitude as num).toDouble();
      if (lat == 0 && lng == 0) return null;
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    TrackingRegistry.add(widget.requestId);
    _reqSub = watchRequest(widget.requestId).listen(_onRequest);
    _startUserTracking();
  }

  Future<void> _startUserTracking() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      _posSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((pos) {
            if (!mounted) return;
            final here = LatLng(pos.latitude, pos.longitude);
            setState(() {
              _userLoc = here;
              // GPS heading is only meaningful while moving; otherwise keep
              // the last known direction.
              if (pos.heading.isFinite && pos.heading >= 0 && pos.speed > 0.5) {
                _heading = pos.heading;
              }
            });
            if (_toDropoff) _maybeRefreshRoute(here);
          }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    TrackingRegistry.remove(widget.requestId);
    _posSub?.cancel();
    // Location sharing is NOT stopped here: it must keep running in the
    // background while the request is active. The sharer stops itself when
    // the request ends.
    _reqSub?.cancel();
    _provSub?.cancel();
    _recenterTimer?.cancel();
    _cancelTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ---------------- data ----------------
  void _onRequest(ServiceRequest? r) {
    if (!mounted || r == null) return;

    final active = kActiveStatuses.contains(r.status);
    if (active && !_sharing) {
      _sharing = true;
      _sharer.start(r.id);
    } else if (!active && _sharing) {
      _sharing = false;
      _sharer.stop();
    }

    final uid = r.providerUid;
    if (uid != null && _provSub == null) {
      _provSub = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen(_onProviderDoc, onError: (_) {});
    }

    if (r.status == RequestStatus.accepted && !_cancelTimerStarted) {
      _cancelTimerStarted = true;
      _cancelTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          final next = _cancelRemaining - const Duration(seconds: 1);
          _cancelRemaining = next.isNegative ? Duration.zero : next;
        });
        if (_cancelRemaining == Duration.zero) _cancelTimer?.cancel();
      });
    }

    final prevStatus = _request?.status;
    setState(() => _request = r);

    // The route's destination changes when the service starts (pickup ->
    // drop-off), so drop the old one and fetch the new one right away.
    if (prevStatus != r.status && r.status == RequestStatus.inProgress) {
      setState(() {
        _routePoints = [];
        _routeKm = null;
        _routeMin = null;
        _routeOrigin = null;
      });
      final from = _routeFrom;
      if (from != null && _toDropoff) _refreshRoute(from);
      return;
    }

    // Route no longer needed once the provider has arrived / job is over.
    if (!_routeRelevant && _routePoints.isNotEmpty) {
      setState(() {
        _routePoints = [];
        _routeKm = null;
        _routeMin = null;
      });
    }
  }

  void _onProviderDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (data == null || !mounted) return;

    AppUser? user;
    try {
      user = userFromMap(snap.id, data);
    } catch (_) {}

    final loc = GeoLocation.fromMap(
      data['currentLocation'] as Map<String, dynamic>?,
    );
    final hasLoc = loc.latitude != 0 || loc.longitude != 0;

    // Optional heading written by the provider app (degrees, 0 = north).
    // Falls back to the bearing between the last two positions.
    final rawHeading =
        (data['currentLocation'] as Map<String, dynamic>?)?['heading'] ??
        data['heading'];

    setState(() {
      _provider = user ?? _provider;
      if (hasLoc) {
        final next = LatLng(loc.latitude, loc.longitude);
        final prev = _providerLoc;
        double? heading;
        if (prev != null &&
            const Distance().as(LengthUnit.Meter, prev, next) >= 2) {
          // Real movement is the most reliable source. Tiny jumps are
          // ignored: GPS noise would make the icon spin.
          heading = _bearing(prev, next);
        } else if (rawHeading is num && rawHeading > 0 && rawHeading <= 360) {
          // Provider-app heading. 0 / -1 usually means "unknown" in
          // Geolocator, so those values are not trusted.
          heading = rawHeading.toDouble();
        } else if (prev == null) {
          // First fix: face the destination until the provider starts moving.
          heading = _bearing(next, _routeTarget);
        }
        if (heading != null) _setProviderHeading(heading);
        _providerLoc = next;
      }
    });

    if (user != null && !_vehicleRequested) {
      _vehicleRequested = true;
      _loadProviderVehicle(user);
    }

    if (hasLoc && _routeRelevant) {
      final from = _routeFrom;
      if (from != null) _maybeRefreshRoute(from);
    }

    // Keep the route in view, unless the driver is moving the map.
    if (hasLoc &&
        _mapReady &&
        DateTime.now().difference(_lastGesture) > const Duration(seconds: 5)) {
      _fitAll();
    }
  }

  /// Initial compass bearing from [a] to [b], 0-360 degrees.
  static double _bearing(LatLng a, LatLng b) {
    final lat1 = a.latitudeInRad;
    final lat2 = b.latitudeInRad;
    final dLng = b.longitudeInRad - a.longitudeInRad;
    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Stores the new heading and keeps [_providerTurns] continuous by moving
  /// along the shortest arc from the previous heading.
  void _setProviderHeading(double heading) {
    var delta = (heading - _providerHeading) % 360;
    if (delta > 180) delta -= 360;
    _providerHeading = heading;
    _providerTurns += delta / 360;
  }

  Future<void> _loadProviderVehicle(AppUser user) async {
    try {
      final v = await fetchActiveVehicle(user);
      if (mounted) setState(() => _providerVehicle = v);
    } catch (_) {}
  }

  // ---------------- route ----------------
  /// Re-fetches the road route when the provider has moved enough, but not
  /// more often than every 8 seconds (the OSRM demo server is rate limited).
  void _maybeRefreshRoute(LatLng from) {
    if (_routing) return;
    final origin = _routeOrigin;
    final moved = origin == null
        ? double.infinity
        : const Distance().as(LengthUnit.Meter, origin, from);
    final recent =
        DateTime.now().difference(_lastRouteAt) < const Duration(seconds: 8);
    if (origin != null && (moved < 40 || recent)) return;
    _refreshRoute(from);
  }

  Future<void> _refreshRoute(LatLng from) async {
    _routing = true;
    _lastRouteAt = DateTime.now();
    final result = await _fetchRoute(from, _routeTarget);
    _routing = false;
    if (!mounted || result == null || !_routeRelevant) return;

    setState(() {
      _routeOrigin = from;
      _routePoints = result.points;
      _routeKm = result.distanceMeters / 1000;
      _routeMin = (result.durationSeconds / 60).ceil();
    });

    if (_mapReady &&
        DateTime.now().difference(_lastGesture) > const Duration(seconds: 5)) {
      _fitAll();
    }
  }

  // ---------------- map ----------------
  void _fitAll() {
    final p = _routeFrom;
    if (p == null) {
      _mapController.move(_routeTarget, 15);
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: _routePoints.length > 1 ? _routePoints : [_routeTarget, p],
        padding: _fitPadding,
        maxZoom: 17,
      ),
    );
  }

  /// After the driver stops touching the map, go back to showing the route.
  void _onGesture() {
    _lastGesture = DateTime.now();
    _recenterTimer?.cancel();
    _recenterTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _mapReady) _fitAll();
    });
  }

  // ---------------- actions ----------------
  void _leave() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _callProvider() async {
    final phone = _provider?.phoneNumber ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number not available')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      if (!await launchUrl(uri) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the dialer')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the dialer')),
      );
    }
  }

  Future<void> _onCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Cancel request?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('The assistance provider will be notified.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Keep request',
              style: TextStyle(color: Colors.black87),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Cancel request',
              style: TextStyle(color: _brandRed, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await cancelRequest(widget.requestId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not cancel the request')),
      );
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back goes home (the page underneath may be the searching page).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: -30,
                    child: _buildMap(),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, top: 8),
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 4,
                        shadowColor: Colors.black38,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _leave,
                          child: const SizedBox(
                            width: 42,
                            height: 42,
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 18,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // OpenStreetMap requires visible attribution.
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        margin: const EdgeInsets.only(top: 4, right: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '© OpenStreetMap contributors',
                          style: TextStyle(fontSize: 10, color: Colors.black87),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildSheet(),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final provider = _providerLoc;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.pickup,
        initialZoom: 15,
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          _mapReady = true;
          _fitAll();
        },
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) _onGesture();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _appPackageName,
        ),
        // Actual road route (same style as the request page).
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                strokeWidth: 5,
                color: const Color.fromARGB(255, 0, 0, 0),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            // Pickup point + label, until the car is being towed to the
            // drop-off.
            if (!_toDropoff)
              Marker(
                point: widget.pickup,
                width: 250,
                height: 120,
                child: _LabeledDot(
                  pill: _AddressPill(
                    tag: 'Pickup',
                    color: _pickupBlue,
                    text: (_request?.pickupAddress ?? '').isEmpty
                        ? 'Pickup point'
                        : _request!.pickupAddress,
                  ),
                  color: Colors.black,
                ),
              ),
            // Drop-off point + label (towing).
            if (_dropoff != null && !_finished)
              Marker(
                point: _dropoff!,
                width: 250,
                height: 120,
                child: _LabeledDot(
                  pill: _AddressPill(
                    tag: 'Drop',
                    color: _brandRed,
                    text: (_request?.dropoffAddress ?? '').isEmpty
                        ? 'Drop-off point'
                        : _request!.dropoffAddress!,
                  ),
                  color: _brandRed,
                ),
              ),
            // The driver: always a live blue GPS dot with a cone showing the
            // direction they are facing. Until the first GPS fix arrives it
            // sits on the pickup point.
            Marker(
              point: _userLoc ?? widget.pickup,
              width: 64,
              height: 64,
              child: _HeadingDot(heading: _heading),
            ),
            if (provider != null)
              Marker(
                point: provider,
                width: 50,
                height: 50,
                // Top-down vehicle that turns to face its direction of travel.
                child: AnimatedRotation(
                  turns: _providerTurns - _vehicleIconFacing / 360,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  child: Image.asset(
                    _providerVehicleIcon,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.local_shipping,
                      color: _brandRed,
                      size: 30,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ---------------- bottom sheet ----------------
  Widget _buildSheet() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.58,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(0, 10, 0, 14 + bottomInset),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildCombinedCard(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _buildActions(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusTitle(RequestStatus s) => switch (s) {
    RequestStatus.pending => 'Waiting for assistance',
    RequestStatus.accepted => 'Driver Accepted Your Request',
    RequestStatus.onTheWay => 'Driver On The Way',
    RequestStatus.arrived => 'Driver Has Arrived',
    RequestStatus.inProgress => 'Service In Progress',
    RequestStatus.completed => 'Service Completed',
    RequestStatus.cancelled =>
      _request?.cancelledBy == 'provider'
          ? 'The assistance provider cancelled'
          : 'Request Cancelled',
    RequestStatus.expired => 'Request Expired',
  };

  /// Status header: title, distance, ETA (plain text) and a progress tracker.
  Widget _buildStatusContent() {
    final p = _routeFrom;
    String? etaValue;
    String? sub;
    if (_routeRelevant && p != null) {
      if (_routeKm != null && _routeMin != null) {
        etaValue = '$_routeMin';
        sub =
            '${_routeKm!.toStringAsFixed(1)} km ${_toDropoff ? 'to drop-off' : 'away'}';
      } else {
        final km = const Distance().as(LengthUnit.Kilometer, p, _routeTarget);
        sub = '${km.toStringAsFixed(1)} km away';
      }
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusTitle(_status),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.near_me_rounded,
                            size: 13,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            sub,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (etaValue != null) ...[
                const SizedBox(width: 10),
                // Plain black text, no red box.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      etaValue,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      'MIN',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          _buildProgress(),
        ],
      ),
    );
  }

  /// One card with provider details, status/progress and service + fare.
  Widget _buildCombinedCard() {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildProviderCard(),
          _buildFareStrip(),
          Container(height: 1, color: Colors.grey.shade200),
          _buildStatusContent(),
        ],
      ),
    );
  }

  /// 4-step progress tracker (hidden for pending / cancelled / expired).
  Widget _buildProgress() {
    final idx = switch (_status) {
      RequestStatus.accepted => 0,
      RequestStatus.onTheWay => 1,
      RequestStatus.arrived => 2,
      RequestStatus.inProgress => 3,
      RequestStatus.completed => 4,
      _ => -1,
    };
    if (idx < 0) return const SizedBox.shrink();

    const labels = ['Accepted', 'On the way', 'Arrived', 'Service'];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: List.generate(labels.length, (i) {
          final done = i <= idx;
          final current = i == idx;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 5,
                    decoration: BoxDecoration(
                      color: done
                          ? (idx == 4 ? _success : _brandRed)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                      color: done ? Colors.black87 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  String _roleLabel(ServiceType t) => switch (t) {
    ServiceType.towTruck => 'Tow truck operator',
    ServiceType.mechanic => 'Mechanic',
    ServiceType.batteryBoost => 'Battery boost technician',
    ServiceType.flatTireChange => 'Tire technician',
    ServiceType.fuelDelivery => 'Fuel delivery driver',
  };

  /// Provider card: avatar, name, role, rating, vehicle + plate, contact.
  Widget _buildProviderCard() {
    final user = _provider;
    final r = _request;

    // Loading skeleton
    if (user == null || r == null) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: _brandRed),
          ),
        ),
      );
    }

    final hasPhoto = user.profileImagePath.isNotEmpty;
    final rating = user.rating;
    final vehicle = _providerVehicle;
    final plate = vehicle?.plateNumber ?? '';
    final vehicleName = vehicle == null
        ? ''
        : '${vehicle.make} ${vehicle.model}'.trim();
    final hasPhone = user.phoneNumber.isNotEmpty;
    final canContact = hasPhone && kActiveStatuses.contains(_status);
    final isLive = kActiveStatuses.contains(_status);

    final fallbackAvatar = ColoredBox(
      color: Colors.grey.shade200,
      child: Icon(Icons.person_rounded, size: 34, color: Colors.grey.shade500),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Avatar + name + role + rating
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // Plain circular photo, no ring.
                  SizedBox(
                    width: 68,
                    height: 68,
                    child: ClipOval(
                      child: hasPhoto
                          ? Image.network(
                              user.profileImagePath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => fallbackAvatar,
                              loadingBuilder: (context, child, progress) =>
                                  progress == null ? child : fallbackAvatar,
                            )
                          : fallbackAvatar,
                    ),
                  ),
                  if (isLive)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name.isEmpty ? 'Assistance' : user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _roleLabel(r.serviceType),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: Colors.black87,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            rating.count > 0
                                ? '${rating.average.toStringAsFixed(1)} (${rating.count})'
                                : 'New provider',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (canContact) ...[
                const SizedBox(width: 8),
                _contactButton(
                  _messageIcon,
                  Icons.chat_bubble_rounded,
                  _messageProvider,
                ),
                const SizedBox(width: 8),
                _contactButton(_callIcon, Icons.phone_rounded, _callProvider),
              ],
            ],
          ),

          // Vehicle strip
          if (plate.isNotEmpty || vehicleName.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _brandRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.directions_car_filled_rounded,
                      size: 20,
                      color: _brandRed,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vehicle',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        Text(
                          vehicleName.isEmpty ? '—' : vehicleName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (plate.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black87, width: 1.6),
                      ),
                      child: Text(
                        plate,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Simple round icon button used for Message / Call (neutral colors).
  Widget _contactButton(String asset, IconData fallback, VoidCallback onTap) {
    return Material(
      color: Colors.grey.shade100,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  Icon(fallback, size: 20, color: Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  /// Fare strip: service type + payment method left, fare right.
  Widget _buildFareStrip() {
    final r = _request;
    if (r == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceTypeTitle(r.serviceType),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 13,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Cash in Person',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'ESTIMATED FARE',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'LKR ${_formatAmount(r.totalAmount)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Opens the phone's messaging app with a new message to the provider.
  Future<void> _messageProvider() async {
    final phone = _provider?.phoneNumber ?? '';
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'sms', path: phone);
    try {
      if (!await launchUrl(uri) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open messages')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open messages')));
    }
  }

  String _formatAmount(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _countdownText() {
    final m = _cancelRemaining.inMinutes;
    final s = _cancelRemaining.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildActions() {
    final s = _status;
    final finished =
        s == RequestStatus.completed ||
        s == RequestStatus.cancelled ||
        s == RequestStatus.expired;

    if (finished) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _leave,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text(
              'Done',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    // cancelRequest only works before the provider is on the way.
    if (s == RequestStatus.accepted) {
      final label = _cancelRemaining > Duration.zero
          ? 'Cancel Request  •  ${_countdownText()}'
          : 'Cancel Request';
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: _onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: _brandRed,
              backgroundColor: Colors.white,
              side: BorderSide(color: _brandRed.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Blue live-location dot. When [heading] is known, a translucent cone
/// points the way the user is facing (like Google Maps).
class _HeadingDot extends StatelessWidget {
  final double? heading;

  const _HeadingDot({this.heading});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (heading != null)
          Transform.rotate(
            angle: heading! * math.pi / 180,
            child: CustomPaint(
              size: const Size(64, 64),
              painter: _ConePainter(),
            ),
          ),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
        ),
      ],
    );
  }
}

class _ConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    const spread = math.pi / 3; // total cone angle (60 degrees)
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.blue.withValues(alpha: 0.55),
          Colors.blue.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    // Up (north) is -pi/2 in canvas angles.
    canvas.drawArc(rect, -math.pi / 2 - spread / 2, spread, true, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// White pill with a coloured tag, e.g. [Pickup] 123 Main Rd.
class _AddressPill extends StatelessWidget {
  final String tag;
  final Color color;
  final String text;

  const _AddressPill({
    required this.tag,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Label pill above a ring-style dot (solid colour with a white centre).
/// The marker is centred on the map point, and the dot is centred inside the
/// marker, so the dot's middle sits exactly on the location. The pill floats
/// above it.
class _LabeledDot extends StatelessWidget {
  final Widget pill;
  final Color color;

  const _LabeledDot({required this.pill, required this.color});

  @override
  Widget build(BuildContext context) {
    // Marker height is 120, so the centre is 60 from the bottom. The dot is
    // 24 high (top at 72); the pill's bottom sits 6 above that (78).
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          bottom: 78,
          left: 0,
          right: 0,
          child: Column(mainAxisSize: MainAxisSize.min, children: [pill]),
        ),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Center(
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
