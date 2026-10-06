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

/// Top-down vehicle image.
const String _providerVehicleIcon = 'assets/images/top-vehicle.png';

/// Which way the image itself points, in degrees clockwise from "up":
/// 0 = front of the vehicle faces the top of the image, 90 = faces right,
/// 180 = faces down, 270 = faces left. Change this if the icon turns the
/// wrong way relative to the direction of travel.
const double _vehicleIconFacing = 0;
const String _appPackageName = 'com.example.roadside_assitance';
const String _userAgent = 'RoadsideAssistance/1.0 (kavidupurnamal@gmail.com)';

/// Time the driver sees counting down next to "Cancel Request".
const Duration _cancelWindow = Duration(minutes: 5);

/// Padding used when fitting the route. The map is laid out 30px taller
/// than what's visible (it extends under the sheet), hence the larger bottom.
const EdgeInsets _fitPadding = EdgeInsets.fromLTRB(50, 90, 50, 70);

String _vehicleAsset(VehicleType type) => switch (type) {
  VehicleType.car => 'assets/images/vehicle-car.png',
  VehicleType.van => 'assets/images/vehicle-van.png',
  VehicleType.motorbike => 'assets/images/vehicle-bike.png',
  VehicleType.threeWheeler => 'assets/images/vehicle-threewheel.png',
  VehicleType.truck => 'assets/images/vehicle-truck.png',
  VehicleType.bus => 'assets/images/vehicle-bus.png',
  VehicleType.towtruck => 'assets/images/vehicle-towtruck.png',
};

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
    _sharer.stop();
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
        title: const Text('Cancel request?'),
        content: const Text('The assistance provider will be notified.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep request'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Cancel request',
              style: TextStyle(color: _brandRed),
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
                        elevation: 3,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _leave,
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.chevron_left,
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
                        color: Colors.white.withValues(alpha: 0.75),
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
            if (_status == RequestStatus.inProgress && _dropoff != null)
              Marker(
                point: _dropoff!,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: const Icon(
                  Icons.location_on,
                  color: Color.fromARGB(255, 210, 0, 0),
                  size: 40,
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
                    errorBuilder: (_, __, ___) => const Icon(
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

  Widget _buildSheet() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + bottomInset),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 15,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              _buildStatusRow(),
              const SizedBox(height: 10),
              Divider(height: 1, color: Colors.grey.shade300),
              const SizedBox(height: 18),
              _buildProviderCard(),
              const SizedBox(height: 14),
              _buildActions(),
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

  /// "14 mins (3.4 km)" from the road route, falling back to the straight
  /// line distance until the first route arrives.
  String? _etaText() {
    if (!_routeRelevant) return null;
    final p = _routeFrom;
    if (p == null) return null;
    if (_routeKm != null && _routeMin != null) {
      final m = _routeMin!;
      return '$m ${m == 1 ? 'min' : 'mins'} (${_routeKm!.toStringAsFixed(1)} km)';
    }
    final km = const Distance().as(LengthUnit.Kilometer, p, _routeTarget);
    return '${km.toStringAsFixed(1)} km away';
  }

  Widget _buildStatusRow() {
    final eta = _etaText();
    final hasPhone = (_provider?.phoneNumber ?? '').isNotEmpty;
    final showCall = hasPhone && kActiveStatuses.contains(_status);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _statusTitle(_status),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (eta != null) ...[
                const SizedBox(height: 4),
                Text(
                  eta,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showCall)
          Material(
            color: _brandRed.withValues(alpha: 0.18),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _callProvider,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.phone, color: _brandRed, size: 24),
              ),
            ),
          ),
      ],
    );
  }

  String _roleLabel(ServiceType t) => switch (t) {
    ServiceType.towTruck => 'Tow truck operator',
    ServiceType.mechanic => 'Mechanic',
    ServiceType.batteryBoost => 'Battery boost technician',
    ServiceType.flatTireChange => 'Tire technician',
    ServiceType.fuelDelivery => 'Fuel delivery driver',
  };

  Widget _buildProviderCard() {
    final user = _provider;
    final r = _request;

    if (user == null || r == null) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final fallbackAvatar = ColoredBox(
      color: Colors.grey.shade300,
      child: Icon(Icons.person, color: Colors.grey.shade600),
    );
    final hasPhoto = user.profileImagePath.isNotEmpty;
    final rating = user.rating;
    final vehicle = _providerVehicle;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: provider + fare
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: hasPhoto
                            ? Image.network(
                                user.profileImagePath,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => fallbackAvatar,
                                loadingBuilder: (context, child, progress) =>
                                    progress == null ? child : fallbackAvatar,
                              )
                            : fallbackAvatar,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name.isEmpty ? 'Assistance' : user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _roleLabel(r.serviceType),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons.star,
                                size: 12,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                rating.count > 0
                                    ? '(${rating.average.toStringAsFixed(1)})'
                                    : '(No ratings yet)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Estimated Fare',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                Text(
                  'LKR ${_formatAmount(r.totalAmount)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Cash in Person',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Right: provider's vehicle
          SizedBox(
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  _vehicleAsset(vehicle?.vehicleType ?? VehicleType.towtruck),
                  height: 54,
                  width: 112,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 54,
                    child: Center(child: Icon(Icons.local_shipping, size: 36)),
                  ),
                ),
                const SizedBox(height: 10),
                if (vehicle != null) ...[
                  Text(
                    '${vehicle.make} ${vehicle.model}'.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    vehicle.plateNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
      return SizedBox(
        width: double.infinity,
        height: 52,
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
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }

    // cancelRequest only works before the provider is on the way.
    if (s == RequestStatus.accepted) {
      final label = _cancelRemaining > Duration.zero
          ? 'Cancel Request (${_countdownText()})'
          : 'Cancel Request';
      return TextButton(
        onPressed: _onCancel,
        style: TextButton.styleFrom(
          foregroundColor: _brandRed,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
