import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../entities/app_user.dart';
import '../../entities/service_request.dart';
import '../../services/customer_location_sharer.dart';
import '../../services/tracking_registry.dart';

const Color _brandRed = Color(0xFFE30613);
const String _assistanceIcon = 'assets/images/assistance1.png';
const String _pickupPinPath = 'assets/images/pickup-point.png';
const String _appPackageName = 'com.example.roadside_assitance';

/// Padding used when fitting both points. The map is laid out 30px taller
/// than what's visible (it extends under the sheet), hence the larger bottom.
const EdgeInsets _fitPadding = EdgeInsets.fromLTRB(50, 90, 50, 70);

/// DRIVER-side tracking page. Shown to the driver (the customer) once an
/// assistance provider accepts their request. Live map with the provider's
/// position, the driver's pickup point and the provider's details. Follows
/// the request status all the way to completed/cancelled.
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

  ServiceRequest? _request;
  AppUser? _provider;
  LatLng? _providerLoc;

  bool _mapReady = false;
  bool _sharing = false;
  DateTime _lastGesture = DateTime.fromMillisecondsSinceEpoch(0);

  RequestStatus get _status => _request?.status ?? RequestStatus.accepted;

  @override
  void initState() {
    super.initState();
    TrackingRegistry.add(widget.requestId);
    _reqSub = watchRequest(widget.requestId).listen(_onRequest);
  }

  @override
  void dispose() {
    TrackingRegistry.remove(widget.requestId);
    _sharer.stop();
    _reqSub?.cancel();
    _provSub?.cancel();
    _recenterTimer?.cancel();
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
    setState(() => _request = r);
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

    setState(() {
      _provider = user ?? _provider;
      if (hasLoc) _providerLoc = LatLng(loc.latitude, loc.longitude);
    });

    // Keep both points in view, unless the driver is moving the map.
    if (hasLoc &&
        _mapReady &&
        DateTime.now().difference(_lastGesture) > const Duration(seconds: 5)) {
      _fitAll();
    }
  }

  // ---------------- map ----------------
  void _fitAll() {
    final p = _providerLoc;
    if (p == null) {
      _mapController.move(widget.pickup, 15);
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: [widget.pickup, p],
        padding: _fitPadding,
        maxZoom: 17,
      ),
    );
  }

  /// After the driver stops touching the map, go back to showing both.
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
        if (provider != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [provider, widget.pickup],
                strokeWidth: 3,
                color: _brandRed.withValues(alpha: 0.5),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: widget.pickup,
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
            if (provider != null)
              Marker(
                point: provider,
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
        maxHeight: MediaQuery.of(context).size.height * 0.55,
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
        child: SingleChildScrollView(
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
              const SizedBox(height: 16),
              _buildProviderCard(),
              const SizedBox(height: 12),
              _buildJobSummary(),
              const SizedBox(height: 16),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  String _statusTitle(RequestStatus s) => switch (s) {
    RequestStatus.pending => 'Waiting for assistance',
    RequestStatus.accepted => 'Assistance accepted your request',
    RequestStatus.onTheWay => 'Assistance is on the way',
    RequestStatus.arrived => 'Assistance has arrived',
    RequestStatus.inProgress => 'Service in progress',
    RequestStatus.completed => 'Service completed',
    RequestStatus.cancelled =>
      _request?.cancelledBy == 'provider'
          ? 'The assistance provider cancelled'
          : 'Request cancelled',
    RequestStatus.expired => 'Request expired',
  };

  Widget _buildStatus() {
    final s = _status;
    final p = _providerLoc;
    final showDistance =
        p != null &&
        (s == RequestStatus.accepted || s == RequestStatus.onTheWay);
    final km = p == null
        ? null
        : const Distance().as(LengthUnit.Kilometer, p, widget.pickup);

    return Column(
      children: [
        Text(
          _statusTitle(s),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        if (showDistance && km != null) ...[
          const SizedBox(height: 4),
          Text(
            '${km.toStringAsFixed(1)} km away',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }

  Widget _buildProviderCard() {
    final user = _provider;
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

    final hasPhoto = user.profileImagePath.isNotEmpty;
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name.isEmpty ? 'Assistance' : user.name,
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

  Widget _buildJobSummary() {
    final r = _request;
    if (r == null) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          serviceTypeTitle(r.serviceType),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        Text(
          'Rs: ${r.totalAmount.toStringAsFixed(2)} · Cash in Person',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
      ],
    );
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
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          onPressed: _onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black87,
            side: BorderSide(color: Colors.grey.shade400),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: const Text('Cancel request'),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
