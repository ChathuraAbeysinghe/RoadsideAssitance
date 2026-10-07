import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../entities/app_user.dart';
import '../../entities/service_request.dart';

const Color _brandRed = Color(0xFFE30613);
const Color _success = Color(0xFF22C55E);
const Color _pickupBlue = Color(0xFF1E88E5);

/// Cash icon shown next to the price.
const String _cashIcon = 'assets/images/cash.png';
const String _appPackageName = 'com.example.roadside_assitance';
const String _userAgent = 'RoadsideAssistance/1.0 (kavidupurnamal@gmail.com)';

/// How long the provider has to answer (never longer than the request's own
/// expiry).
const int _maxRespondSeconds = 120;

/// Padding used when fitting the route. The map is laid out 30px taller than
/// what's visible (it extends under the sheet), hence the larger bottom.
const EdgeInsets _fitPadding = EdgeInsets.fromLTRB(50, 110, 50, 90);

class _RouteResult {
  final List<LatLng> points;
  final double km;
  final int minutes;

  const _RouteResult({
    required this.points,
    required this.km,
    required this.minutes,
  });
}

/// Road route between two points from the OSRM public demo server (testing
/// only, same as the tracking pages). Returns null if it can't be fetched.
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
      km: (first['distance'] as num).toDouble() / 1000,
      minutes: ((first['duration'] as num).toDouble() / 60).ceil(),
    );
  } catch (_) {
    return null;
  }
}

/// Full-screen "new request" page shown to a provider. Accept or Decline.
/// Closes by itself when the time runs out or when another provider takes
/// the request. Pops `true` if this provider accepted it.
class IncomingRequestPage extends StatefulWidget {
  final ServiceRequest request;

  const IncomingRequestPage({super.key, required this.request});

  @override
  State<IncomingRequestPage> createState() => _IncomingRequestPageState();
}

class _IncomingRequestPageState extends State<IncomingRequestPage> {
  final _mapController = MapController();
  Timer? _timer;
  StreamSubscription<ServiceRequest?>? _sub;

  late final int _total;
  late int _left;
  bool _busy = false;
  bool _closing = false;
  double? _distanceKm;
  LatLng? _me; // this provider's position (blue dot)
  AppUser? _driver; // the customer who made the request
  List<LatLng> _routePoints = []; // road route pickup -> drop-off
  double? _tripKm; // delivery distance (pickup -> drop-off)
  int? _tripMin; // delivery estimated time in minutes
  bool _mapReady = false;

  ServiceRequest get _r => widget.request;

  /// Splits the request's vehicle label into (name, plate) for two lines.
  /// If the label has no recognisable separator it all stays on line one.
  (String, String?) get _vehicleParts {
    final label = (_r.vehicleLabel ?? '').trim();
    for (final sep in const [' · ', ' • ', ' | ', ' (', ', ', ' – ', ' — ']) {
      final i = label.indexOf(sep);
      if (i > 0) {
        final name = label.substring(0, i).trim();
        final plate = label
            .substring(i + sep.length)
            .replaceAll(')', '')
            .trim();
        if (name.isNotEmpty && plate.isNotEmpty) return (name, plate);
      }
    }
    return (label, null);
  }

  /// Delivery distance / time: the request's own values when it has them,
  /// otherwise what the road route gave.
  double? get _deliveryKm => _r.distanceKm ?? _tripKm;
  int? get _deliveryMin => _r.durationMin ?? _tripMin;
  LatLng get _pickup => LatLng(_r.pickup.latitude, _r.pickup.longitude);
  LatLng? get _dropoff => _r.dropoff == null
      ? null
      : LatLng(_r.dropoff!.latitude, _r.dropoff!.longitude);

  @override
  void initState() {
    super.initState();
    final remaining = _r.expiresAt.difference(DateTime.now()).inSeconds;
    _total = remaining.clamp(5, _maxRespondSeconds);
    _left = _total;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) _decline();
    });

    // Close if someone else takes it, or the customer cancels.
    _sub = watchRequest(_r.id).listen((latest) {
      if (!mounted || _closing || latest == null) return;
      if (latest.status != RequestStatus.pending) {
        _close(false, 'This request is no longer available');
      }
    });

    _loadDistance();
    _loadRoute();
    _loadDriver();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Loads the details of the driver (customer) who made the request.
  Future<void> _loadDriver() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_r.customerUid)
          .get();
      final data = doc.data();
      if (data == null || !mounted) return;
      setState(() => _driver = userFromMap(doc.id, data));
    } catch (_) {}
  }

  /// Fetches the road route from pickup to drop-off (towing) and fits the map
  /// to it.
  Future<void> _loadRoute() async {
    final drop = _dropoff;
    if (drop == null) return;
    final route = await _fetchRoute(_pickup, drop);
    if (!mounted || route == null || route.points.length < 2) return;
    setState(() {
      _routePoints = route.points;
      _tripKm = route.km;
      _tripMin = route.minutes;
    });
    _fitRoute();
  }

  void _fitRoute() {
    if (!_mapReady || _routePoints.length < 2) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: _routePoints,
        padding: _fitPadding,
        maxZoom: 17,
      ),
    );
  }

  Future<void> _loadDistance() async {
    try {
      final p =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              timeLimit: Duration(seconds: 5),
            ),
          );
      final here = LatLng(p.latitude, p.longitude);
      final km = const Distance().as(LengthUnit.Kilometer, here, _pickup);
      if (mounted) {
        setState(() {
          _me = here;
          _distanceKm = km.toDouble();
        });
      }
    } catch (_) {}
  }

  // ---------------- actions ----------------
  void _close(bool accepted, [String? message]) {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
    Navigator.of(context).pop(accepted);
  }

  void _decline() => _close(false);

  Future<void> _accept() async {
    if (_busy || _closing) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _close(false);
      return;
    }
    setState(() => _busy = true);

    AcceptResult result;
    try {
      result = await acceptRequest(requestId: _r.id, providerUid: uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not accept. Try again.')),
      );
      return;
    }
    if (!mounted) return;

    switch (result) {
      case AcceptResult.success:
        _close(true, 'Request accepted');
      case AcceptResult.alreadyTaken:
        _close(false, 'Another provider already accepted this request');
      case AcceptResult.expired:
        _close(false, 'This request has expired');
      case AcceptResult.notFound:
        _close(false, 'This request is no longer available');
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
    final dropoff = _dropoff;
    final me = _me;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _pickup,
        initialZoom: 15,
        initialCameraFit: dropoff == null
            ? null
            : CameraFit.coordinates(
                coordinates: [_pickup, dropoff],
                padding: _fitPadding,
              ),
        onMapReady: () {
          _mapReady = true;
          _fitRoute();
        },
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _appPackageName,
        ),
        // Actual road route from pickup to drop-off (same style as the
        // tracking pages).
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                strokeWidth: 5,
                color: Colors.black,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            // Pickup point + label.
            Marker(
              point: _pickup,
              width: 250,
              height: 120,
              child: _LabeledDot(
                pill: _AddressPill(
                  tag: 'Pickup',
                  color: _pickupBlue,
                  text: _r.pickupAddress.isEmpty
                      ? 'Pickup point'
                      : _r.pickupAddress,
                ),
                color: Colors.black,
              ),
            ),
            // Drop-off point + label (towing).
            if (dropoff != null)
              Marker(
                point: dropoff,
                width: 250,
                height: 120,
                child: _LabeledDot(
                  pill: _AddressPill(
                    tag: 'Drop',
                    color: _brandRed,
                    text: (_r.dropoffAddress ?? '').isEmpty
                        ? 'Drop-off point'
                        : _r.dropoffAddress!,
                  ),
                  color: _brandRed,
                ),
              ),
            // This provider: blue live dot.
            if (me != null)
              Marker(
                point: me,
                width: 64,
                height: 64,
                child: const _HeadingDot(),
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
                    _buildHeader(),
                    _buildDriverCard(),
                    _buildFareStrip(),
                    const SizedBox(height: 12),
                    _buildDetails(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: _buildButtons(),
            ),
          ],
        ),
      ),
    );
  }

  /// Title, distance and the time left to answer (plain text, like the
  /// tracking page's status header) plus a progress bar.
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New ${serviceTypeTitle(_r.serviceType)} request',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    if (_distanceKm != null) ...[
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
                            '${_distanceKm!.toStringAsFixed(1)} km away',
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
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (_left / _total).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(_brandRed),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Time left to respond',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                '${_left < 0 ? 0 : _left} sec',
                style: const TextStyle(
                  fontSize: 14,
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

  /// Driver (customer) card: avatar, name, rating.
  Widget _buildDriverCard() {
    final user = _driver;

    // Loading skeleton
    if (user == null) {
      return const SizedBox(
        height: 100,
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
              // Vehicle details on the right.
              if ((_r.vehicleLabel ?? '').isNotEmpty) ...[
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VEHICLE',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _vehicleParts.$1,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      if (_vehicleParts.$2 != null)
                        Text(
                          _vehicleParts.$2!,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: Colors.grey.shade700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Delivery distance and estimated time (tow truck), shown on the right of
  /// the header like on the tracking page.
  Widget _buildTripInfo() {
    final km = _dropoff == null ? null : _deliveryKm;
    final min = _dropoff == null ? null : _deliveryMin;
    if (km == null && min == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (km != null)
            Text(
              '${km.toStringAsFixed(1)} km',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          if (min != null) ...[
            const SizedBox(height: 2),
            Text(
              '$min min',
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

  /// Fare strip: service type + payment method left, fare right.
  Widget _buildFareStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceTypeTitle(_r.serviceType),
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
                      _r.paymentMethod == 'cash' ? 'Cash in Person' : 'Card',
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    _cashIcon,
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.payments_outlined,
                      size: 22,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'LKR ${_formatAmount(_r.totalAmount)}',
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

  /// Request details in a soft grey card (same as the tracking page).
  Widget _buildDetails() {
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
            _r.pickupAddress,
            maxLines: 2,
          ),
          if (_r.dropoffAddress != null && _r.dropoffAddress!.isNotEmpty)
            _infoRow(
              Icons.flag_outlined,
              'Drop-off',
              _r.dropoffAddress!,
              maxLines: 2,
            ),
          if (_r.liters != null)
            _infoRow(
              Icons.local_gas_station_outlined,
              'Fuel',
              '${_r.liters} L · ${_r.fuelType ?? ''}'.trim(),
            ),
          if (_r.notes.isNotEmpty)
            _infoRow(Icons.note_alt_outlined, 'Notes', _r.notes),
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

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 54,
            child: OutlinedButton(
              onPressed: _busy ? null : _decline,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                backgroundColor: Colors.white,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Decline',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _busy ? null : _accept,
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
                  : const Text(
                      'Accept',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ],
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

/// Blue live-location dot (this provider).
class _HeadingDot extends StatelessWidget {
  const _HeadingDot();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Center(
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}
