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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  Future<void> _launch(Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
    try {
      if (!await launchUrl(uri, mode: mode)) _snack('Could not open app');
    } catch (_) {
      _snack('Could not open app');
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
          label: 'Start Driving',
          next: RequestStatus.onTheWay,
        ),
        RequestStatus.onTheWay => (
          label: 'I Have Arrived',
          next: RequestStatus.arrived,
        ),
        RequestStatus.arrived => (
          label: 'Start Service',
          next: RequestStatus.inProgress,
        ),
        RequestStatus.inProgress => (
          label: 'Complete Job',
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Complete Job?', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
            job.paymentMethod == 'cash'
                ? 'Collect ${money(job.totalAmount)} in cash from the customer before completing.'
                : 'Confirm the service is finished.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Complete'),
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
      if (done && next == RequestStatus.completed) {
        _showFinalSummary(job);
      }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Job?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'The customer will be notified. Frequent cancellations can lower your rating.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Job'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Job', style: TextStyle(color: _brandRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _advance(job, RequestStatus.cancelled);
  }

  void _showFinalSummary(ServiceRequest job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 60),
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'Service Completed!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
              ),
              const SizedBox(height: 32),
              Text('SERVICE DETAILS', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 13)),
              const SizedBox(height: 16),
              _row(Icons.build_circle_outlined, serviceTypeTitle(job.serviceType)),
              _row(Icons.location_on_outlined, job.pickupAddress),
              if (job.dropoffAddress != null && job.dropoffAddress!.isNotEmpty)
                _row(Icons.flag_outlined, 'Drop-off: ${job.dropoffAddress}'),
              if (job.vehicleLabel != null)
                _row(Icons.directions_car_outlined, job.vehicleLabel!),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Final Price', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(money(job.totalAmount), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: _brandRed)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Payment Method', style: TextStyle(fontSize: 15, color: Colors.grey)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      job.paymentMethod == 'cash' ? 'Cash in person' : job.paymentMethod, 
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w600)
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                    shadowColor: _brandRed.withValues(alpha: 0.4),
                  ),
                  child: const Text('Done', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    if (_missing) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
        backgroundColor: Colors.white,
        body: const Center(child: Text('This request no longer exists.', style: TextStyle(color: Colors.grey))),
      );
    }
    if (job == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0),
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
                    padding: const EdgeInsets.only(left: 16, top: 12),
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
                      margin: const EdgeInsets.only(top: 12, right: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '© OpenStreetMap',
                        style: TextStyle(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 46,
                  child: _circle(Icons.my_location, _fit, size: 48, iconSize: 24, color: _brandRed),
                ),
              ],
            ),
          ),
          _buildSheet(job),
        ],
      ),
    );
  }

  Widget _circle(IconData icon, VoidCallback onTap, {double size = 44, double iconSize = 24, Color color = Colors.black87}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: color, size: iconSize),
          ),
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
              Polyline(points: _route, strokeWidth: 5, color: _brandRed.withValues(alpha: 0.8)),
            ],
          ),
        MarkerLayer(
          rotate: true,
          markers: [
            Marker(
              point: pickup,
              width: 44,
              height: 44,
              alignment: Alignment.topCenter,
              child: const Icon(Icons.location_on, color: Colors.blue, size: 44),
            ),
            if (dropoff != null)
              Marker(
                point: dropoff,
                width: 44,
                height: 44,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.flag, color: Colors.black, size: 38),
              ),
            if (hasLive)
              Marker(
                point: LatLng(live.latitude, live.longitude),
                width: 36,
                height: 36,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4),
                    ],
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 20),
                ),
              ),
            if (_me != null)
              Marker(
                point: _me!,
                width: 40,
                height: 40,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8),
                    ],
                  ),
                  child: Image.asset(
                    _assistanceIcon,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.local_shipping, color: _brandRed, size: 24),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSheet(ServiceRequest job) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _progress(job.status),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          serviceTypeTitle(job.serviceType),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor(job.status).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          statusLabel(job.status),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: statusColor(job.status),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _customerCard(job),
                  const SizedBox(height: 24),
                  _row(Icons.location_on_outlined, job.pickupAddress, iconColor: Colors.blue),
                  if (job.dropoffAddress != null && job.dropoffAddress!.isNotEmpty)
                    _row(Icons.flag_outlined, 'Drop-off: ${job.dropoffAddress}', iconColor: Colors.black87),
                  if (kActiveStatuses.contains(job.status) &&
                      _routeKm != null &&
                      _routeMin != null)
                    _row(
                      Icons.alt_route,
                      '${_routeKm!.toStringAsFixed(1)} km - about $_routeMin min away',
                      iconColor: _brandRed,
                    ),
                  if (job.vehicleLabel != null)
                    _row(Icons.directions_car_outlined, job.vehicleLabel!),
                  if (job.serviceType == ServiceType.fuelDelivery && job.liters != null)
                    _row(
                      Icons.local_gas_station_outlined,
                      '${job.liters} L ${job.fuelType ?? ''}',
                    ),
                  if (job.notes.isNotEmpty)
                    _row(Icons.sticky_note_2_outlined, 'Note: ${job.notes}', iconColor: Colors.orange.shade700),
                  _row(
                    Icons.payments_outlined,
                    '${money(job.totalAmount)} - ${job.paymentMethod == 'cash' ? 'Cash' : job.paymentMethod}',
                    iconColor: Colors.green,
                  ),
                  const SizedBox(height: 24),
                  ..._actions(job),
                ],
              ),
            ),
          ),
        ],
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
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i < done ? _brandRed : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(IconData icon, String text, {Color iconColor = Colors.black54}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(text, style: TextStyle(fontSize: 15, color: Colors.grey.shade800, fontWeight: FontWeight.w500)),
            ),
          ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.grey.shade100,
            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo.isEmpty
                ? Icon(Icons.person, color: Colors.grey.shade400, size: 28)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (c?.name.isNotEmpty ?? false) ? c!.name : 'Customer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    phone,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
          if (canContact) ...[
            _contactButton(
              Icons.chat_bubble_outline_rounded,
              () => _launch(Uri(scheme: 'sms', path: phone)),
              color: Colors.blue,
            ),
            const SizedBox(width: 10),
            _contactButton(
              Icons.phone_rounded,
              () => _launch(Uri(scheme: 'tel', path: phone)),
              color: Colors.green,
              filled: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _contactButton(IconData icon, VoidCallback onTap, {bool filled = false, required Color color}) {
    return Container(
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: filled ? Colors.white : color),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(ServiceRequest job) {
    if (job.status == RequestStatus.completed) {
      return [
        _banner(Icons.check_circle_outline, Colors.green, 'Job Completed',
            'You earned ${money(job.totalAmount)}. Great work!'),
        const SizedBox(height: 16),
        _primary('Back to Home', () => Navigator.of(context).pop()),
      ];
    }
    if (job.status == RequestStatus.cancelled ||
        job.status == RequestStatus.expired) {
      return [
        _banner(
          Icons.cancel_outlined,
          Colors.grey.shade600,
          job.cancelledBy == 'customer'
              ? 'Customer Cancelled'
              : 'Job Cancelled',
          'You are free to take new requests.',
        ),
        const SizedBox(height: 16),
        _primary('Back to Home', () => Navigator.of(context).pop(), isSecondary: true),
      ];
    }

    final next = _nextAction(job.status);
    if (next == null) return [];
    
    return [
      if (job.status == RequestStatus.accepted || job.status == RequestStatus.onTheWay)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _navigateExternally,
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Open in Google Maps', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue.shade700,
                side: BorderSide(color: Colors.blue.shade200),
                backgroundColor: Colors.blue.shade50,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ),
      Row(
        children: [
          Expanded(
            child: _primary(
              next.label,
              () => _advance(job, next.next),
              isLoading: _busy,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _busy ? null : () => _cancelJob(job),
                child: Center(
                  child: Icon(Icons.close_rounded, color: Colors.red.shade600),
                ),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _primary(String label, VoidCallback onTap, {bool isLoading = false, bool isSecondary = false}) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isSecondary ? Colors.grey.shade200 : _brandRed,
          foregroundColor: isSecondary ? Colors.black87 : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: isSecondary ? 0 : 4,
          shadowColor: isSecondary ? Colors.transparent : _brandRed.withValues(alpha: 0.4),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
              )
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _banner(IconData icon, Color color, String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
