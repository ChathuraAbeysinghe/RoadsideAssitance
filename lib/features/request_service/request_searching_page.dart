import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../entities/app_user.dart';
import '../../entities/service_request.dart';

const Color _brandRed = Color(0xFFE30613);

const String _searchMapImage = 'assets/images/search-map.png';
const String _searchMagnifierImage = 'assets/images/search-magnifier.png';
const String _pickupPinPath = 'assets/images/pickup-point.png';
const String _appPackageName = 'com.example.roadside_assitance';

/// Shown after the customer confirms. Listens to the request document:
///  - pending  -> searching UI, widening the radius every stage
///  - accepted (or later) -> provider details
///  - expired  -> "no assistance found" with Try again
class RequestSearchingPage extends StatefulWidget {
  final String requestId;
  final LatLng pickup;

  const RequestSearchingPage({
    super.key,
    required this.requestId,
    required this.pickup,
  });

  @override
  State<RequestSearchingPage> createState() => _RequestSearchingPageState();
}

class _RequestSearchingPageState extends State<RequestSearchingPage>
    with SingleTickerProviderStateMixin {
  final _mapController = MapController();

  /// Drives the map + magnifying glass animation.
  late final AnimationController _searchAnim;

  StreamSubscription<ServiceRequest?>? _sub;
  Timer? _timer;

  ServiceRequest? _request;
  int _stage = 0;
  int _elapsedSeconds = 0;

  /// Lets only the progress bars rebuild every second.
  final ValueNotifier<int> _elapsedNotifier = ValueNotifier<int>(0);
  Future<AppUser?>? _providerFuture;

  RequestStatus get _status => _request?.status ?? RequestStatus.pending;

  int get _stageSeconds => kSearchTimeout.inSeconds ~/ kSearchRadiiKm.length;

  @override
  void initState() {
    super.initState();
    _searchAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _sub = watchRequest(widget.requestId).listen(_onRequest);
    _startTimer();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _searchAnim.dispose();
    _elapsedNotifier.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ---------------- Logic ----------------
  void _onRequest(ServiceRequest? r) {
    if (!mounted || r == null) return;

    if (r.status != RequestStatus.pending &&
        r.status != RequestStatus.cancelled &&
        r.status != RequestStatus.expired &&
        r.providerUid != null) {
      _providerFuture ??= _loadProvider(r.providerUid!);
    }
    if (r.status != RequestStatus.pending) _timer?.cancel();

    setState(() => _request = r);
  }

  Future<AppUser?> _loadProvider(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data();
    if (data == null) return null;
    return userFromMap(uid, data);
  }

  void _startTimer() {
    _timer?.cancel();
    _elapsedSeconds = 0;
    _elapsedNotifier.value = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || _status != RequestStatus.pending) return;
      _elapsedSeconds++;
      _elapsedNotifier.value = _elapsedSeconds;

      if (_elapsedSeconds >= kSearchTimeout.inSeconds) {
        _timer?.cancel();
        try {
          await expireRequest(widget.requestId);
        } catch (_) {}
        return;
      }

      final newStage = (_elapsedSeconds ~/ _stageSeconds).clamp(
        0,
        kSearchRadiiKm.length - 1,
      );
      if (newStage != _stage) {
        setState(() => _stage = newStage);
        _fitMapToRadius();
        try {
          await updateSearchRadius(widget.requestId, kSearchRadiiKm[newStage]);
        } catch (_) {}
      }
    });
  }

  List<LatLng> _radiusExtent(double km) {
    const distance = Distance();
    final meters = km * 1000;
    return [0.0, 90.0, 180.0, 270.0]
        .map((bearing) => distance.offset(widget.pickup, meters, bearing))
        .toList();
  }

  void _fitMapToRadius() {
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: _radiusExtent(kSearchRadiiKm[_stage]),
        padding: const EdgeInsets.fromLTRB(30, 90, 30, 320),
      ),
    );
  }

  void _leave() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _onCancelPressed() async {
    if (_status != RequestStatus.pending) {
      _leave();
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel request?'),
        content: const Text('We will stop looking for nearby assistance.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep searching'),
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
    } catch (_) {}
    _leave();
  }

  Future<void> _onTryAgain() async {
    try {
      final renewed = await renewRequest(widget.requestId);
      if (!renewed || !mounted) return;
      setState(() => _stage = 0);
      _fitMapToRadius();
      _startTimer();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not restart the search')),
      );
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final searching = _status == RequestStatus.pending;

    return PopScope(
      // While searching, back asks for confirmation instead of leaving.
      canPop: !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onCancelPressed();
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
                          onTap: _onCancelPressed,
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
    final radiusKm = kSearchRadiiKm[_stage];
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.pickup,
        initialZoom: 12,
        initialCameraFit: CameraFit.coordinates(
          coordinates: _radiusExtent(kSearchRadiiKm.first),
          padding: const EdgeInsets.fromLTRB(30, 90, 30, 320),
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _appPackageName,
        ),
        // Search radius.
        CircleLayer(
          circles: [
            CircleMarker(
              point: widget.pickup,
              radius: radiusKm * 1000,
              useRadiusInMeter: true,
              color: _brandRed.withValues(alpha: 0.08),
              borderColor: _brandRed.withValues(alpha: 0.4),
              borderStrokeWidth: 1.5,
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
          ],
        ),
      ],
    );
  }

  Widget _buildSheet() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
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
          _buildSheetContent(),
        ],
      ),
    );
  }

  Widget _buildSheetContent() {
    switch (_status) {
      case RequestStatus.pending:
        return _buildSearching();
      case RequestStatus.expired:
        return _buildExpired();
      case RequestStatus.cancelled:
        return _buildMessage(
          icon: Icons.cancel_outlined,
          color: Colors.grey,
          title: 'Request cancelled',
          subtitle: 'This request was cancelled.',
        );
      case RequestStatus.accepted:
      case RequestStatus.onTheWay:
      case RequestStatus.arrived:
      case RequestStatus.inProgress:
      case RequestStatus.completed:
        return _buildAccepted();
    }
  }

  // ---- Searching ----
  Widget _buildSearching() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Looking For Nearby Assistance',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          'Searching within ${kSearchRadiiKm[_stage].toStringAsFixed(0)} km…',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        _buildStageBars(),
        const SizedBox(height: 18),
        _buildSearchAnimation(),
        const SizedBox(height: 10),
        const Text(
          'Estimated wait time: 2 min',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: _onCancelPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              side: BorderSide(color: Colors.grey.shade400),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text('Cancel request'),
          ),
        ),
      ],
    );
  }

  /// Map image that gently pulses, with a magnifying glass sweeping
  /// around it in a circle.
  Widget _buildSearchAnimation() {
    const double size = 110;
    return SizedBox(
      width: size + 40,
      height: size + 40,
      child: AnimatedBuilder(
        animation: _searchAnim,
        builder: (context, _) {
          final t = _searchAnim.value * 2 * math.pi;
          final pulse = 1 + 0.04 * math.sin(t);
          final dx = math.cos(t) * 20;
          final dy = math.sin(t) * 14;

          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: pulse,
                child: Image.asset(
                  _searchMapImage,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.map,
                    size: size * 0.8,
                    color: Colors.green.shade300,
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(dx, dy),
                child: Transform.rotate(
                  angle: math.sin(t) * 0.12,
                  child: Image.asset(
                    _searchMagnifierImage,
                    width: size * 0.7,
                    height: size * 0.7,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.search,
                      size: size * 0.6,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// One bar per stage. Past stages are full, the current one fills
  /// smoothly with elapsed time, future ones are empty.
  Widget _buildStageBars() {
    return ValueListenableBuilder<int>(
      valueListenable: _elapsedNotifier,
      builder: (context, elapsed, _) {
        return Row(
          children: [
            for (var i = 0; i < kSearchRadiiKm.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _stageBar(i, elapsed)),
            ],
          ],
        );
      },
    );
  }

  Widget _stageBar(int index, int elapsed) {
    final double target;
    if (index < _stage) {
      target = 1;
    } else if (index == _stage) {
      target = ((elapsed - _stage * _stageSeconds) / _stageSeconds).clamp(
        0.0,
        1.0,
      );
    } else {
      target = 0;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: Colors.grey.shade400)),
            // Linear tween over 1s matches the timer tick, so the fill
            // moves continuously instead of jumping.
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: target),
              duration: const Duration(seconds: 1),
              curve: Curves.linear,
              builder: (context, value, _) => FractionallySizedBox(
                widthFactor: value,
                alignment: Alignment.centerLeft,
                child: const ColoredBox(
                  color: _brandRed,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Expired ----
  Widget _buildExpired() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.search_off, size: 56, color: Colors.grey.shade500),
        const SizedBox(height: 12),
        const Text(
          'No assistance found nearby',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          "We couldn't find an available provider right now.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        _primaryButton('Try again', _onTryAgain),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: _leave,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              side: BorderSide(color: Colors.grey.shade400),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text('Close'),
          ),
        ),
      ],
    );
  }

  // ---- Accepted ----
  Widget _buildAccepted() {
    return FutureBuilder<AppUser?>(
      future: _providerFuture,
      builder: (context, snap) {
        final provider = snap.data;
        final name = (provider?.name.isNotEmpty ?? false)
            ? provider!.name
            : 'A provider';
        final rating = provider?.rating;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 56, color: Colors.green),
            const SizedBox(height: 12),
            const Text(
              'Assistance found!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '$name accepted your request',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            if (rating != null && rating.count > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, size: 18, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    rating.average.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            _primaryButton('Done', _leave),
          ],
        );
      },
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: color),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        _primaryButton('Close', _leave),
      ],
    );
  }

  Widget _primaryButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _brandRed,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
