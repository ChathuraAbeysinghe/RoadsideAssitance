import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../entities/app_user.dart';
import '../../entities/service_request.dart';
import '../../services/tracking_registry.dart';

const Color _brandRed = Color(0xFFE30613);
const Color _success = Color(0xFF22C55E);
const String _assistanceIcon = 'assets/images/assistance1.png';
const String _pickupPinPath = 'assets/images/pickup-point.png';
const String _appPackageName = 'com.example.roadside_assitance';

/// Contact button icons (same files as the driver tracking page).
const String _messageIcon = 'assets/images/message.png';
const String _callIcon = 'assets/images/call.png';

/// The map is laid out 30px taller than what's visible (it extends under the
/// sheet), hence the larger bottom padding.
const EdgeInsets _fitPadding = EdgeInsets.fromLTRB(50, 90, 50, 70);

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

  bool _mapReady = false;
  bool _busy = false;
  bool _driverRequested = false;
  DateTime _lastGesture = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------------- derived ----------------
  LatLng get _pickup => LatLng(_r!.pickup.latitude, _r!.pickup.longitude);

  LatLng? get _dropoff => _r?.dropoff == null
      ? null
      : LatLng(_r!.dropoff!.latitude, _r!.dropoff!.longitude);

  /// The driver's live position, when their app is sharing it.
  LatLng? get _driverLive {
    final loc = _r?.customerLocation;
    if (loc == null || (loc.latitude == 0 && loc.longitude == 0)) return null;
    return LatLng(loc.latitude, loc.longitude);
  }

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
    setState(() => _r = r);

    if (!_driverRequested) {
      _driverRequested = true;
      _loadDriver(r.customerUid);
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
              distanceFilter: 10,
            ),
          ).listen((p) {
            if (!mounted) return;
            setState(() => _me = LatLng(p.latitude, p.longitude));
            _maybeFit();
          }, onError: (_) {});
    } catch (_) {}
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
    final points = <LatLng>[
      _pickup,
      if (_dropoff != null) _dropoff!,
      if (_me != null) _me!,
      if (_driverLive != null) _driverLive!,
    ];
    if (points.length == 1) {
      _mapController.move(_pickup, 15);
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
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
    final live = _driverLive;

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
        // Pickup -> drop-off (towing).
        if (dropoff != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [_pickup, dropoff],
                strokeWidth: 4,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ],
          ),
        // Provider -> where they're heading next.
        if (me != null && !_finished)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [me, _target],
                strokeWidth: 3,
                color: _brandRed.withValues(alpha: 0.5),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: _pickup,
              width: 40,
              height: 48,
              alignment: Alignment.topCenter,
              child: Image.asset(
                _pickupPinPath,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.location_on,
                  color: Colors.green,
                  size: 40,
                ),
              ),
            ),
            if (dropoff != null)
              Marker(
                point: dropoff,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: const Icon(
                  Icons.location_on,
                  color: Color.fromARGB(255, 210, 0, 0),
                  size: 40,
                ),
              ),
            // The driver's live position (blue dot).
            if (live != null && !_finished)
              Marker(
                point: live,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4),
                    ],
                  ),
                ),
              ),
            // This provider.
            if (me != null)
              Marker(
                point: me,
                width: 40,
                height: 40,
                child: Image.asset(
                  _assistanceIcon,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.local_shipping,
                    color: _brandRed,
                    size: 30,
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
                  children: [_buildCombinedCard(), _buildDetails()],
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
                              errorBuilder: (_, __, ___) => fallbackAvatar,
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
              errorBuilder: (_, __, ___) =>
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
            ],
          ),
          _buildProgress(),
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
  String _formatTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _money(double v) => 'LKR ${_formatAmount(v)}';

  /// Remaining request details (pickup, drop-off, fuel, notes, fee breakdown).
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
          _infoRow(Icons.location_on_outlined, 'Pickup', r.pickupAddress),
          if (r.dropoffAddress != null && r.dropoffAddress!.isNotEmpty)
            _infoRow(Icons.flag_outlined, 'Drop-off', r.dropoffAddress!),
          if (r.distanceKm != null || r.durationMin != null)
            _infoRow(
              Icons.route_outlined,
              'Trip',
              [
                if (r.distanceKm != null)
                  '${r.distanceKm!.toStringAsFixed(1)} km',
                if (r.durationMin != null) '${r.durationMin} min',
              ].join(' · '),
            ),
          if (r.liters != null)
            _infoRow(
              Icons.local_gas_station_outlined,
              'Fuel',
              '${r.liters} L · ${r.fuelType ?? ''}'.trim(),
            ),
          if (r.notes.isNotEmpty)
            _infoRow(Icons.note_alt_outlined, 'Notes', r.notes),
          Divider(height: 14, color: Colors.grey.shade300),
          _infoRow(
            Icons.receipt_long_outlined,
            'Service fee',
            _money(r.serviceFee),
          ),
          if (r.fuelCost > 0)
            _infoRow(
              Icons.local_gas_station_outlined,
              'Fuel cost',
              _money(r.fuelCost),
            ),
          if (r.createdAt != null)
            _infoRow(
              Icons.schedule_outlined,
              'Requested',
              _formatTime(r.createdAt!),
            ),
          if (r.acceptedAt != null)
            _infoRow(
              Icons.check_circle_outline,
              'Accepted',
              _formatTime(r.acceptedAt!),
            ),
          if (r.completedAt != null)
            _infoRow(Icons.done_all, 'Completed', _formatTime(r.completedAt!)),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
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
                  : (step == null ? _back : () => _advance(step.$2)),
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
          if (_canCancel) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: _busy ? null : _confirmCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brandRed,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: _brandRed.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  'Cancel Job',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
