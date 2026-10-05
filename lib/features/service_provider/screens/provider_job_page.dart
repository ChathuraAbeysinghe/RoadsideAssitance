import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../entities/app_user.dart';
import '../../../entities/service_request.dart';
import '../../../services/provider_location_service.dart';
import '../services/provider_repository.dart';
import '../services/routing_service.dart';
import 'provider_ui_helpers.dart';

const Color _brandRed = Color(0xFFE30613);
const String _appPackageName = 'com.example.roadside_assitance';
const String _assistanceIcon = 'assets/images/assistance1.png';

/// The provider's screen for one accepted request: map with the customer's
/// live position and route, call / SMS, and the status flow
/// accepted -> on the way -> arrived -> in progress -> completed.
class ProviderJobPage extends StatefulWidget {
  final String requestId;
  const ProviderJobPage({super.key, required this.requestId});

  @override
  State<ProviderJobPage> createState() => _ProviderJobPageState();
}

class _ProviderJobPageState extends State<ProviderJobPage> {
  final _repo = ProviderRepository();
  final _map = MapController();

  late final String _uid;
  StreamSubscription<ServiceRequest?>? _jobSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _meSub;

  ServiceRequest? _job;
  bool _missing = false;
  LatLng? _me;
  AppUser? _customer;
  bool _customerRequested = false;

  List<LatLng> _route = const [];
  double? _routeKm;
  int? _routeMin;
  LatLng? _routeTo;
  DateTime _routeAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _routing = false;

  bool _mapReady = false;
  bool _fitted = false;
  bool _busy = false;
  bool _refreshedAfterEnd = false;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _jobSub = watchRequest(widget.requestId).listen(_onJob);
    if (_uid.isNotEmpty) {
      _meSub = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .snapshots()
          .listen(_onMe);
    }
  }

  @override
  void dispose() {
    _jobSub?.cancel();
    _meSub?.cancel();
    _map.dispose();
    super.dispose();
  }

  // ---------------- Data ----------------
  void _onJob(ServiceRequest? job) {
    if (!mounted) return;
    if (job == null) {
      setState(() => _missing = true);
      return;
    }
    if (!_customerRequested) {
      _customerRequested = true;
      _loadCustomer(job.customerUid);
    }
    setState(() => _job = job);

    if (!kActiveStatuses.contains(job.status) && !_refreshedAfterEnd) {
      // Job finished or was cancelled by the customer: location sharing
      // can now follow the availability switch again.
      _refreshedAfterEnd = true;
      ProviderLocationService.instance.refresh();
    }
    _maybeRoute();
  }

  void _onMe(DocumentSnapshot<Map<String, dynamic>> snap) {
    final loc = snap.data()?['currentLocation'] as Map<String, dynamic>?;
    if (loc == null || !mounted) return;
    final lat = (loc['latitude'] as num?)?.toDouble() ?? 0;
    final lng = (loc['longitude'] as num?)?.toDouble() ?? 0;
    if (lat == 0 && lng == 0) return;
    setState(() => _me = LatLng(lat, lng));
    _maybeRoute();
  }

  Future<void> _loadCustomer(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data != null && mounted) {
        setState(() => _customer = userFromMap(uid, data));
      }
    } catch (_) {}
  }

  /// Where the provider is heading right now.
  LatLng? get _target {
    final j = _job;
    if (j == null) return null;
    if (j.serviceType == ServiceType.towTruck &&
        j.status == RequestStatus.inProgress &&
        j.dropoff != null) {
      return LatLng(j.dropoff!.latitude, j.dropoff!.longitude);
    }
    final live = j.customerLocation;
    final heading =
        j.status == RequestStatus.accepted || j.status == RequestStatus.onTheWay;
    if (heading && live != null && (live.latitude != 0 || live.longitude != 0)) {
      return LatLng(live.latitude, live.longitude);
    }
    return LatLng(j.pickup.latitude, j.pickup.longitude);
  }

  Future<void> _maybeRoute() async {
    final from = _me;
    final to = _target;
    final job = _job;
    if (from == null || to == null || job == null || _routing) return;
    if (!kActiveStatuses.contains(job.status)) return;

    const d = Distance();
    final stale =
        DateTime.now().difference(_routeAt) > const Duration(seconds: 20);
    final targetMoved =
        _routeTo == null || d.as(LengthUnit.Meter, _routeTo!, to) > 50;
    if (!(stale || targetMoved)) return;

    _routing = true;
    _routeAt = DateTime.now();
    final result = await fetchRoute(from, to);
    _routing = false;
    if (!mounted || result == null) return;

    setState(() {
      _route = result.points;
      _routeKm = result.distanceKm;
      _routeMin = result.durationMin;
      _routeTo = to;
    });
    if (!_fitted) _fit();
  }

  void _fit() {
    final me = _me;
    final to = _target;
    if (!_mapReady || me == null || to == null) return;
    _fitted = true;
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [me, to],
        padding: const EdgeInsets.fromLTRB(50, 100, 50, 90),
        maxZoom: 17,
      ),
    );
  }

  // ---------------- Actions ----------------
  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _launch(Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
    try {
      if (!await launchUrl(uri, mode: mode)) _snack('Could not open that app');
    } catch (_) {
      _snack('Could not open that app');
    }
  }

  Future<void> _navigateExternally() async {
    final t = _target;
    if (t == null) return;
    await _launch(
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${t.latitude},${t.longitude}&travelmode=driving',
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  ({String label, RequestStatus next})? _nextAction(RequestStatus s) =>
      switch (s) {
        RequestStatus.accepted => (
          label: 'Start driving to customer',
          next: RequestStatus.onTheWay,
        ),
        RequestStatus.onTheWay => (
          label: 'I have arrived',
          next: RequestStatus.arrived,
        ),
        RequestStatus.arrived => (
          label: 'Start service',
          next: RequestStatus.inProgress,
        ),
        RequestStatus.inProgress => (
          label: 'Complete job',
          next: RequestStatus.completed,
        ),
        _ => null,
      };

  Future<void> _advance(ServiceRequest job, RequestStatus next) async {
    if (_busy) return;

    if (next == RequestStatus.completed) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Complete this job?'),
          content: Text(
            job.paymentMethod == 'cash'
                ? 'Collect ${money(job.totalAmount)} in cash from the customer before completing.'
                : 'Confirm the service is finished.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Not yet'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Complete', style: TextStyle(color: _brandRed)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      final done = await _repo.setJobStatus(job, next);
      if (!done) _snack('Could not update the job. It may have changed.');
      if (done && next == RequestStatus.onTheWay) _fitted = false;
    } catch (_) {
      _snack('Could not update the job. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelJob(ServiceRequest job) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this job?'),
        content: const Text(
          'The customer will be notified. Frequent cancellations can lower your rating.',
        ),
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
    if (ok != true) return;
    await _advance(job, RequestStatus.cancelled);
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final job = _job;
    if (_missing) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This request no longer exists.')),
      );
    }
    if (job == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator(color: _brandRed)),
      );
    }

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
                  child: _buildMap(job),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, top: 8),
                    child: _circle(
                      Icons.chevron_left,
                      () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
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
                Positioned(
                  right: 16,
                  bottom: 46,
                  child: _circle(Icons.my_location, _fit, size: 48),
                ),
              ],
            ),
          ),
          _buildSheet(job),
        ],
      ),
    );
  }

  Widget _circle(IconData icon, VoidCallback onTap, {double size = 40}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildMap(ServiceRequest job) {
    final pickup = LatLng(job.pickup.latitude, job.pickup.longitude);
    final live = job.customerLocation;
    final hasLive =
        live != null && (live.latitude != 0 || live.longitude != 0);
    final dropoff = job.dropoff == null
        ? null
        : LatLng(job.dropoff!.latitude, job.dropoff!.longitude);

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _me ?? pickup,
        initialZoom: 15,
        onMapReady: () {
          _mapReady = true;
          _fit();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _appPackageName,
        ),
        if (_route.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(points: _route, strokeWidth: 5, color: Colors.black),
            ],
          ),
        MarkerLayer(
          rotate: true,
          markers: [
            Marker(
              point: pickup,
              width: 40,
              height: 40,
              alignment: Alignment.topCenter,
              child: const Icon(Icons.location_on, color: _brandRed, size: 40),
            ),
            if (dropoff != null)
              Marker(
                point: dropoff,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.flag, color: Colors.black, size: 34),
              ),
            if (hasLive)
              Marker(
                point: LatLng(live.latitude, live.longitude),
                width: 34,
                height: 34,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4),
                    ],
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 18),
                ),
              ),
            if (_me != null)
              Marker(
                point: _me!,
                width: 34,
                height: 34,
                child: Image.asset(
                  _assistanceIcon,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.local_shipping, color: _brandRed, size: 28),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSheet(ServiceRequest job) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.62,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottom),
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
              const SizedBox(height: 14),
              _progress(job.status),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      serviceTypeTitle(job.serviceType),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor(job.status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      statusLabel(job.status),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor(job.status),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _customerCard(job),
              const SizedBox(height: 14),
              _row(Icons.location_on_outlined, job.pickupAddress),
              if (job.dropoffAddress != null && job.dropoffAddress!.isNotEmpty)
                _row(Icons.flag_outlined, 'Drop-off: ${job.dropoffAddress}'),
              if (kActiveStatuses.contains(job.status) &&
                  _routeKm != null &&
                  _routeMin != null)
                _row(
                  Icons.alt_route,
                  '${_routeKm!.toStringAsFixed(1)} km - about $_routeMin min away',
                ),
              if (job.vehicleLabel != null)
                _row(Icons.directions_car_outlined, job.vehicleLabel!),
              if (job.serviceType == ServiceType.fuelDelivery && job.liters != null)
                _row(
                  Icons.local_gas_station_outlined,
                  '${job.liters} L ${job.fuelType ?? ''}',
                ),
              if (job.notes.isNotEmpty)
                _row(Icons.sticky_note_2_outlined, job.notes),
              _row(
                Icons.payments_outlined,
                '${money(job.totalAmount)} - ${job.paymentMethod == 'cash' ? 'Cash in person' : job.paymentMethod}',
              ),
              const SizedBox(height: 16),
              ..._actions(job),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progress(RequestStatus s) {
    const steps = [
      RequestStatus.accepted,
      RequestStatus.onTheWay,
      RequestStatus.arrived,
      RequestStatus.inProgress,
    ];
    final done = s == RequestStatus.completed ? 4 : steps.indexOf(s) + 1;
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i < done ? _brandRed : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.black87),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _customerCard(ServiceRequest job) {
    final c = _customer;
    final phone = c?.phoneNumber ?? '';
    final photo = c?.profileImagePath ?? '';
    final canContact = phone.isNotEmpty && kActiveStatuses.contains(job.status);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo.isEmpty
                ? Icon(Icons.person, color: Colors.grey.shade500)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (c?.name.isNotEmpty ?? false) ? c!.name : 'Customer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (phone.isNotEmpty)
                  Text(
                    phone,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          if (canContact) ...[
            _contactButton(
              Icons.sms_outlined,
              () => _launch(Uri(scheme: 'sms', path: phone)),
            ),
            const SizedBox(width: 8),
            _contactButton(
              Icons.call,
              () => _launch(Uri(scheme: 'tel', path: phone)),
              filled: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _contactButton(IconData icon, VoidCallback onTap, {bool filled = false}) {
    return Material(
      color: filled ? _brandRed : Colors.white,
      shape: CircleBorder(
        side: BorderSide(color: filled ? _brandRed : Colors.grey.shade400),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 20, color: filled ? Colors.white : Colors.black87),
        ),
      ),
    );
  }

  List<Widget> _actions(ServiceRequest job) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(30));

    if (job.status == RequestStatus.completed) {
      return [
        _banner(Icons.check_circle, Colors.green, 'Job completed',
            'You earned ${money(job.totalAmount)}.'),
        const SizedBox(height: 12),
        _primary('Done', () => Navigator.of(context).pop(), shape),
      ];
    }
    if (job.status == RequestStatus.cancelled ||
        job.status == RequestStatus.expired) {
      return [
        _banner(
          Icons.cancel_outlined,
          Colors.grey,
          job.cancelledBy == 'customer'
              ? 'The customer cancelled this request'
              : 'This job was cancelled',
          'You are free to take new requests.',
        ),
        const SizedBox(height: 12),
        _primary('Back to home', () => Navigator.of(context).pop(), shape),
      ];
    }

    final next = _nextAction(job.status);
    return [
      if (next != null)
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _busy ? null : () => _advance(job, next.next),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: shape,
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    next.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _navigateExternally,
          icon: const Icon(Icons.navigation_outlined, size: 20),
          label: const Text('Open in Google Maps'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black87,
            side: BorderSide(color: Colors.grey.shade400),
            shape: shape,
          ),
        ),
      ),
      if (job.status != RequestStatus.inProgress)
        TextButton(
          onPressed: _busy ? null : () => _cancelJob(job),
          child: const Text(
            'Cancel job',
            style: TextStyle(color: Colors.black54),
          ),
        ),
    ];
  }

  Widget _banner(IconData icon, Color color, String title, String sub) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Text(sub, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _primary(String label, VoidCallback onTap, RoundedRectangleBorder shape) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _brandRed,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: shape,
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
