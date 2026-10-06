import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../entities/app_user.dart';
import '../../entities/service_request.dart';
import '../../services/tracking_registry.dart';

const Color _brandRed = Color(0xFFE30613);
const String _assistanceIcon = 'assets/images/assistance1.png';
const String _pickupPinPath = 'assets/images/pickup-point.png';
const String _appPackageName = 'com.example.roadside_assitance';

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
        title: const Text('Cancel this job?'),
        content: const Text('The driver will be told that you cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep job'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel job', style: TextStyle(color: _brandRed)),
          ),
        ],
      ),
    );
    if (confirm == true) _advance(RequestStatus.cancelled);
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
                      elevation: 3,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _back,
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
                  color: Colors.black,
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

  Widget _buildSheet() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.62,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomInset),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),
            _buildStatus(),
            const SizedBox(height: 14),
            // Only the details scroll; the buttons stay visible.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildDriverCard(),
                    const SizedBox(height: 12),
                    _buildDetails(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildActions(),
          ],
        ),
      ),
    );
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

  Widget _buildStatus() {
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

    return Column(
      children: [
        Text(
          _statusTitle(_status),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        if (showDistance && km != null) ...[
          const SizedBox(height: 4),
          Text(
            '${km.toStringAsFixed(1)} km to ${toDropoff ? 'drop-off' : 'the driver'}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }

  // ---- driver ----
  Widget _buildDriverCard() {
    final user = _driver;
    final fallbackAvatar = ColoredBox(
      color: Colors.grey.shade300,
      child: Icon(Icons.person, color: Colors.grey.shade600),
    );

    if (user == null) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final rating = user.rating;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 54,
              height: 54,
              child: user.profileImagePath.isNotEmpty
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Driver',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
                Text(
                  user.name.isEmpty ? 'Driver' : user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (user.phoneNumber.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.phone, size: 14, color: Colors.grey.shade700),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          user.phoneNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 3),
                    Text(
                      rating.count > 0
                          ? '${rating.average.toStringAsFixed(1)} (${rating.count})'
                          : 'No ratings yet',
                      style: TextStyle(
                        fontSize: 13,
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
    );
  }

  // ---- request details ----
  String _formatTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _money(double v) => 'Rs: ${v.toStringAsFixed(2)}';

  Widget _buildDetails() {
    final r = _r!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow(
          Icons.build_circle_outlined,
          'Service',
          serviceTypeTitle(r.serviceType),
        ),
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
        if (r.vehicleLabel != null)
          _infoRow(Icons.directions_car_outlined, 'Vehicle', r.vehicleLabel!),
        if (r.liters != null)
          _infoRow(
            Icons.local_gas_station_outlined,
            'Fuel',
            '${r.liters} L · ${r.fuelType ?? ''}'.trim(),
          ),
        if (r.notes.isNotEmpty)
          _infoRow(Icons.note_alt_outlined, 'Notes', r.notes),
        const SizedBox(height: 4),
        Divider(height: 1, color: Colors.grey.shade300),
        const SizedBox(height: 4),
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
        _infoRow(Icons.payments_outlined, 'Total', _money(r.totalAmount)),
        _infoRow(
          Icons.account_balance_wallet_outlined,
          'Payment',
          r.paymentMethod == 'cash' ? 'Cash in Person' : 'Card',
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
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _busy
                ? null
                : (step == null ? _back : () => _advance(step.$2)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandRed,
              foregroundColor: Colors.white,
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
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
        if (_canCancel)
          TextButton(
            onPressed: _busy ? null : _confirmCancel,
            child: const Text(
              'Cancel job',
              style: TextStyle(color: Colors.black87),
            ),
          ),
      ],
    );
  }
}
