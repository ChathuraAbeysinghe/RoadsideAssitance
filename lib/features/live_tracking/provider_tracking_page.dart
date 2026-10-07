import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../entities/app_user.dart';
import '../../entities/service_request.dart';
import '../../services/tracking_registry.dart';

const Color _brandRed = Color(0xFFE30613);
const Color _success = Color(0xFF22C55E);
const Color _pickupBlue = Color(0xFF1E88E5);
const Color _dropOrange = Color(0xFFFB8C00);
const String _appPackageName = 'com.example.roadside_assitance';
const String _userAgent = 'RoadsideAssistance/1.0 (kavidupurnamal@gmail.com)';

/// Contact button icons (same files as the driver tracking page).
const String _messageIcon = 'assets/images/message.png';
const String _callIcon = 'assets/images/call.png';

/// The map is laid out 30px taller than what's visible (it extends under the
/// sheet), hence the larger bottom padding.
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

/// OSRM public demo server (testing only, same as the driver tracking page).
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

/// ASSISTANCE PROVIDER-side tracking page for an accepted job.
///
/// Shows the DRIVER's details (the customer who asked for help), every detail
/// of the request, a live map (provider, driver's live position, pickup and
/// drop-off) and the buttons that move the job along:
///   Start driving -> I have arrived -> Start service -> Complete service
/// plus Cancel job while the service hasn't started.
///
/// Opened automatically by IncomingRequestListener right after Accept, and
/// can be opened from the provider's home page (ongoing requests) with just
/// the request id.
class ProviderTrackingPage extends StatefulWidget {
  final String requestId;

  const ProviderTrackingPage({super.key, required this.requestId});

  @override
  State<ProviderTrackingPage> createState() => _ProviderTrackingPageState();
}

class _ProviderTrackingPageState extends State<ProviderTrackingPage> {
  final _mapController = MapController();

  StreamSubscription<ServiceRequest?>? _reqSub;
  StreamSubscription<Position>? _posSub;
  Timer? _recenterTimer;

  ServiceRequest? _r;
  AppUser? _driver; // the customer who made the request
  LatLng? _me; // this provider's position

  // Direction this provider is heading (degrees clockwise from north);
  // last known while moving. [_headingTurns] is the unwrapped (continuous)
  // version used for animation so the arrow always turns the short way round.
  double _heading = 0;
  double _headingTurns = 0;
  bool _hasHeading = false;

  // Road route provider -> pickup (or drop-off once towing).
  List<LatLng> _routePoints = [];
  bool _routing = false;
  LatLng? _routeOrigin;
  DateTime _lastRouteAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _mapReady = false;
  bool _busy = false;
  bool _driverRequested = false;
  DateTime _lastGesture = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------------- derived ----------------
  LatLng get _pickup => LatLng(_r!.pickup.latitude, _r!.pickup.longitude);

  LatLng? get _dropoff => _r?.dropoff == null
      ? null
      : LatLng(_r!.dropoff!.latitude, _r!.dropoff!.longitude);

  RequestStatus get _status => _r?.status ?? RequestStatus.accepted;

  bool get _finished =>
      _status == RequestStatus.completed ||
      _status == RequestStatus.cancelled ||
      _status == RequestStatus.expired;

  /// Where the provider is heading: the drop-off once a towing job is under
  /// way, otherwise the pickup.
  LatLng get _target {
    final d = _dropoff;
    if (d != null && _status == RequestStatus.inProgress) return d;
    return _pickup;
  }

  /// Towing job under way: the route now leads to the drop-off.
  bool get _toDropoff =>
      _status == RequestStatus.inProgress && _dropoff != null;

  /// The route is only shown while heading to the pickup or the drop-off.
  bool get _routeRelevant =>
      _status == RequestStatus.accepted ||
      _status == RequestStatus.onTheWay ||
      _toDropoff;

  @override
  void initState() {
    super.initState();
    TrackingRegistry.add(widget.requestId);
    _reqSub = watchRequest(widget.requestId).listen(_onRequest);
    _startPosition();
  }

  @override
  void dispose() {
    TrackingRegistry.remove(widget.requestId);
    _reqSub?.cancel();
    _posSub?.cancel();
    _recenterTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ---------------- data ----------------
  void _onRequest(ServiceRequest? r) {
    if (!mounted || r == null) return;
    final prevStatus = _r?.status;
    setState(() => _r = r);

    if (!_driverRequested) {
      _driverRequested = true;
      _loadDriver(r.customerUid);
    }

    // The route's destination depends on the status (pickup -> drop-off),
    // so drop the old route and fetch the right one.
    if (prevStatus != r.status) {
      setState(() {
        _routePoints = [];
        _routeOrigin = null;
      });
      final me = _me;
      if (me != null && _routeRelevant) _refreshRoute(me);
    }
  }

  Future<void> _loadDriver(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data == null || !mounted) return;
      setState(() => _driver = userFromMap(doc.id, data));
    } catch (_) {}
  }

  Future<void> _startPosition() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() => _me = LatLng(last.latitude, last.longitude));
      }
    } catch (_) {}

    try {
      _posSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((p) {
            if (!mounted) return;
            final here = LatLng(p.latitude, p.longitude);
            setState(() {
              final prev = _me;
              if (p.heading.isFinite && p.heading >= 0 && p.speed > 0.5) {
                // GPS heading is only meaningful while moving.
                _setHeading(p.heading);
              } else if (prev != null &&
                  const Distance().as(LengthUnit.Meter, prev, here) >= 3) {
                // Otherwise use the direction between the last two fixes.
                _setHeading(_bearing(prev, here));
              }
              _me = here;
            });
            if (_routeRelevant) _maybeRefreshRoute(here);
            _maybeFit();
          }, onError: (_) {});
    } catch (_) {}
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

  /// Stores the new heading and keeps [_headingTurns] continuous by moving
  /// along the shortest arc from the previous heading.
  void _setHeading(double heading) {
    var delta = (heading - _heading) % 360;
    if (delta > 180) delta -= 360;
    _heading = heading;
    _headingTurns += delta / 360;
    _hasHeading = true;
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
    final target = _target;
    final result = await _fetchRoute(from, target);
    _routing = false;
    if (!mounted || result == null || !_routeRelevant || target != _target) {
      return;
    }

    setState(() {
      _routeOrigin = from;
      _routePoints = result.points;
    });

    if (_mapReady &&
        DateTime.now().difference(_lastGesture) > const Duration(seconds: 5)) {
      _fitAll();
    }
  }

  // ---------------- map ----------------
  void _maybeFit() {
    if (_mapReady &&
        _r != null &&
        DateTime.now().difference(_lastGesture) > const Duration(seconds: 5)) {
      _fitAll();
    }
  }

  void _fitAll() {
    if (_r == null) return;
    final me = _me;
    if (me == null) {
      _mapController.move(_target, 15);
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: _routePoints.length > 1 ? _routePoints : [_target, me],
        padding: _fitPadding,
        maxZoom: 17,
      ),
    );
  }

  /// After the provider stops touching the map, show everything again.
  void _onGesture() {
    _lastGesture = DateTime.now();
    _recenterTimer?.cancel();
    _recenterTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _mapReady) _fitAll();
    });
  }

  // ---------------- actions ----------------
  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _back() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _advance(RequestStatus next) async {
    if (_busy) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final ok = await updateJobStatus(
        requestId: widget.requestId,
        providerUid: uid,
        next: next,
      );
      if (!ok) _snack('This request was cancelled or changed');
    } catch (_) {
      _snack('Could not update the job. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Cancel this job?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('The driver will be told that you cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Keep job',
              style: TextStyle(color: Colors.black87),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Cancel job',
              style: TextStyle(color: _brandRed, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) _advance(RequestStatus.cancelled);
  }

  /// Confirmation sheet that slides up from the bottom.
  Future<void> _confirmComplete() async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 22),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 36,
                    color: _success,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Complete service?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Confirm that the service is finished. The driver will be '
                'told that the job is completed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'Yes, complete',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: TextButton.styleFrom(foregroundColor: Colors.black87),
                child: const Text(
                  'Not yet',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm == true) _advance(RequestStatus.completed);
  }

  Future<void> _callDriver() async {
    final phone = _driver?.phoneNumber ?? '';
    if (phone.isEmpty) {
      _snack('Phone number not available');
      return;
    }
    try {
      if (!await launchUrl(Uri(scheme: 'tel', path: phone))) {
        _snack('Could not open the dialer');
      }
    } catch (_) {
      _snack('Could not open the dialer');
    }
  }

  /// Opens the phone's messaging app with a new message to the driver.
  Future<void> _messageDriver() async {
    final phone = _driver?.phoneNumber ?? '';
    if (phone.isEmpty) return;
    try {
      if (!await launchUrl(Uri(scheme: 'sms', path: phone))) {
        _snack('Could not open messages');
      }
    } catch (_) {
      _snack('Could not open messages');
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    if (_r == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator(color: _brandRed)),
      );
    }

    return Scaffold(
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
                        onTap: _back,
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
    );
  }

  Widget _buildMap() {
    final me = _me;
    final dropoff = _dropoff;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _pickup,
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
        // Actual road route (same style as the driver tracking page).
        if (_routePoints.isNotEmpty && _routeRelevant)
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
                point: _pickup,
                width: 250,
                height: 92,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AddressPill(
                      tag: 'Pickup',
                      color: _pickupBlue,
                      text: _r!.pickupAddress.isEmpty
                          ? 'Pickup point'
                          : _r!.pickupAddress,
                    ),
                    const _PointDot(color: Colors.black),
                  ],
                ),
              ),
            // Drop-off point + label (towing).
            if (dropoff != null && !_finished)
              Marker(
                point: dropoff,
                width: 250,
                height: 92,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AddressPill(
                      tag: 'Drop',
                      color: _dropOrange,
                      text: (_r!.dropoffAddress ?? '').isEmpty
                          ? 'Drop-off point'
                          : _r!.dropoffAddress!,
                    ),
                    const _PointDot(color: _brandRed),
                  ],
                ),
              ),
            // This provider: blue live dot with a direction cone.
            if (me != null)
              Marker(
                point: me,
                width: 64,
                height: 64,
                child: _HeadingDot(
                  turns: _headingTurns,
                  showCone: _hasHeading && !_finished,
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
        maxHeight: MediaQuery.of(context).size.height * 0.62,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            // Only the details scroll; the buttons stay visible.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCombinedCard(),
                    _buildDetails(),
                    _buildCancelLink(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _buildActions(),
            ),
          ],
        ),
      ),
    );
  }

  /// One card with driver details, fare and status/progress.
  Widget _buildCombinedCard() {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDriverCard(),
          _buildFareStrip(),
          Container(height: 1, color: Colors.grey.shade200),
          _buildStatusContent(),
        ],
      ),
    );
  }

  // ---- driver ----
  /// Driver card: avatar, name, role, rating, vehicle, contact buttons.
  Widget _buildDriverCard() {
    final user = _driver;
    final r = _r;

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
    final vehicleName = r.vehicleLabel ?? '';
    final canContact = user.phoneNumber.isNotEmpty && !_finished;
    final isLive = !_finished;

    final fallbackAvatar = ColoredBox(
      color: Colors.grey.shade200,
      child: Icon(Icons.person_rounded, size: 34, color: Colors.grey.shade500),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
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
                      user.name.isEmpty ? 'Driver' : user.name,
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
                      'Driver',
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
                                : 'New driver',
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
                  _messageDriver,
                ),
                const SizedBox(width: 8),
                _contactButton(_callIcon, Icons.phone_rounded, _callDriver),
              ],
            ],
          ),

          // Vehicle strip
          if (vehicleName.isNotEmpty) ...[
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
                          vehicleName,
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

  // ---- fare ----
  /// Fare strip: service type + payment method left, fare right.
  Widget _buildFareStrip() {
    final r = _r;
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
                      r.paymentMethod == 'cash' ? 'Cash in Person' : 'Card',
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
                'TOTAL FARE',
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

  String _formatAmount(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ---- status ----
  String _statusTitle(RequestStatus s) => switch (s) {
    RequestStatus.pending => 'Waiting',
    RequestStatus.accepted => 'Request accepted',
    RequestStatus.onTheWay => 'On the way to the driver',
    RequestStatus.arrived => 'You have arrived',
    RequestStatus.inProgress => 'Service in progress',
    RequestStatus.completed => 'Job completed',
    RequestStatus.cancelled =>
      _r?.cancelledBy == 'provider'
          ? 'You cancelled this job'
          : 'The driver cancelled this request',
    RequestStatus.expired => 'Request expired',
  };

  /// Status header: title, distance and a progress tracker.
  Widget _buildStatusContent() {
    final me = _me;
    final toDropoff = _status == RequestStatus.inProgress && _dropoff != null;
    final showDistance =
        me != null &&
        (_status == RequestStatus.accepted ||
            _status == RequestStatus.onTheWay ||
            toDropoff);
    final km = me == null
        ? null
        : const Distance().as(LengthUnit.Kilometer, me, _target);

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
                    if (showDistance && km != null) ...[
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
                            '${km.toStringAsFixed(1)} km to ${toDropoff ? 'drop-off' : 'the driver'}',
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
              _buildTripInfo(),
            ],
          ),
          _buildProgress(),
        ],
      ),
    );
  }

  /// Trip distance and duration, shown on the right of the status header.
  Widget _buildTripInfo() {
    final r = _r;
    if (r == null || (r.distanceKm == null && r.durationMin == null)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (r.distanceKm != null)
            Text(
              '${r.distanceKm!.toStringAsFixed(1)} km',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          if (r.durationMin != null) ...[
            const SizedBox(height: 2),
            Text(
              '${r.durationMin} min',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
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

  // ---- request details ----
  String _money(double v) => 'LKR ${_formatAmount(v)}';

  /// Remaining request details (pickup, drop-off, fuel, notes, fuel cost).
  Widget _buildDetails() {
    final r = _r!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow(
            Icons.location_on_outlined,
            'Pickup',
            r.pickupAddress,
            maxLines: 2,
          ),
          if (r.dropoffAddress != null && r.dropoffAddress!.isNotEmpty)
            _infoRow(
              Icons.flag_outlined,
              'Drop-off',
              r.dropoffAddress!,
              maxLines: 2,
            ),
          if (r.liters != null)
            _infoRow(
              Icons.local_gas_station_outlined,
              'Fuel',
              '${r.liters} L · ${r.fuelType ?? ''}'.trim(),
            ),
          if (r.notes.isNotEmpty)
            _infoRow(Icons.note_alt_outlined, 'Notes', r.notes),
          if (r.fuelCost > 0)
            _infoRow(
              Icons.local_gas_station_outlined,
              'Fuel cost',
              _money(r.fuelCost),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {int? maxLines}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: maxLines == null ? null : TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- buttons ----
  /// (label, next status) for the current status, or null when finished.
  (String, RequestStatus)? get _nextStep => switch (_status) {
    RequestStatus.accepted => ('Start driving', RequestStatus.onTheWay),
    RequestStatus.onTheWay => ('I have arrived', RequestStatus.arrived),
    RequestStatus.arrived => ('Start service', RequestStatus.inProgress),
    RequestStatus.inProgress => ('Complete service', RequestStatus.completed),
    _ => null,
  };

  /// updateJobStatus allows cancelling until the service has started.
  bool get _canCancel =>
      _status == RequestStatus.accepted ||
      _status == RequestStatus.onTheWay ||
      _status == RequestStatus.arrived;

  Widget _buildActions() {
    final step = _nextStep;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _busy
                  ? null
                  : (step == null
                        ? _back
                        : () => step.$2 == RequestStatus.completed
                              ? _confirmComplete()
                              : _advance(step.$2)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandRed,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _brandRed.withValues(alpha: 0.6),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      step?.$1 ?? 'Done',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Small red text at the very bottom of the scrollable content.
  Widget _buildCancelLink() {
    if (!_canCancel) return const SizedBox.shrink();
    return Center(
      child: TextButton(
        onPressed: _busy ? null : _confirmCancel,
        style: TextButton.styleFrom(
          foregroundColor: _brandRed,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          'Cancel job',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
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

/// Pickup / drop-off marker: a ring-style dot (solid colour with a white
/// centre) under the label. The dot's centre sits exactly on the map point.
class _PointDot extends StatelessWidget {
  final Color color;

  const _PointDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
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
        // Pushes the dot's centre onto the point (marker is bottom-anchored).
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Blue live-location dot. The translucent cone rotates smoothly to point in
/// the direction of travel (like Google Maps).
class _HeadingDot extends StatelessWidget {
  final double turns;
  final bool showCone;

  const _HeadingDot({required this.turns, required this.showCone});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showCone)
            AnimatedRotation(
              turns: turns,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
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
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
          ),
        ],
      ),
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
