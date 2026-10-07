import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../entities/app_user.dart';
import '../../entities/service_request.dart';
import '../../services/customer_location_sharer.dart';

const Color _brandRed = Color(0xFFE30613);
const Color _success = Color(0xFF22C55E);

const String _searchMapImage = 'assets/images/search-map.jpg';
const String _searchMagnifierImage = 'assets/images/search-magnifier.png';
const String _assistanceIcon = 'assets/images/assistance1.png';
const String _appPackageName = 'com.example.roadside_assitance';

/// Search radius for each stage (one per progress bar):
/// stage 0 -> 5 km, stage 1 -> 10 km, stage 2 -> 15 km.
const List<double> _stageRadiiKm = [5, 10, 15];

/// TODO: set this to the Firestore collection your requests live in.
/// It's used to widen `searchRadiusKm` on the request document so providers
/// further away start seeing it. If you already have a helper for this in
/// service_request.dart, call that instead of [_updateRadiusInFirestore].
const String _requestsCollection = 'service_requests';

/// Padding used when fitting the search circle into the visible map.
/// The map is laid out 30px taller than what's visible (it extends under
/// the sheet), so the bottom is 30 larger to keep the pin truly centered.
const EdgeInsets _mapFitPadding = EdgeInsets.fromLTRB(40, 40, 40, 70);

/// Shown after the customer confirms. Listens to the request document:
///  - pending  -> searching UI, widening the radius every stage (5/10/15 km)
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
    with TickerProviderStateMixin {
  final _mapController = MapController();
  final _sharer = CustomerLocationSharer();

  /// Drives the map + magnifying glass animation in the sheet.
  late final AnimationController _searchAnim;

  /// Drives the radar (pulse rings + rotating sweep) on the map.
  late final AnimationController _radarAnim;

  StreamSubscription<ServiceRequest?>? _sub;

  /// Live nearby providers shown on the map while searching.
  StreamSubscription<List<NearbyProvider>>? _providersSub;
  List<NearbyProvider> _providers = const [];

  /// Provider whose info card is open on the map, and a cache of the
  /// details we've already loaded (name, rating, phone, photo).
  String? _selectedUid;
  final Map<String, Future<AppUser?>> _providerDetails = {};
  Timer? _timer;

  /// After the user stops moving the map, this puts it back to the default
  /// view (centered on the pickup, whole search circle visible).
  Timer? _recenterTimer;
  static const Duration _recenterDelay = Duration(seconds: 5);

  ServiceRequest? _request;
  int _stage = 0;
  int _elapsedSeconds = 0;

  /// Lets only the progress bars rebuild every second.
  final ValueNotifier<int> _elapsedNotifier = ValueNotifier<int>(0);
  Future<AppUser?>? _providerFuture;

  RequestStatus get _status => _request?.status ?? RequestStatus.pending;

  int get _stageSeconds => kSearchTimeout.inSeconds ~/ 3;

  /// Current search radius, driven by the stage (5 -> 10 -> 15 km).
  double get _currentRadiusKm => _stageRadiiKm[_stage];

  @override
  void initState() {
    super.initState();
    _searchAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _radarAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _sub = watchRequest(widget.requestId).listen(_onRequest);
    _startTimer();
  }

  @override
  void dispose() {
    _sharer.stop();
    _sub?.cancel();
    _providersSub?.cancel();
    _timer?.cancel();
    _recenterTimer?.cancel();
    _searchAnim.dispose();
    _radarAnim.dispose();
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
    if (r.status != RequestStatus.pending) {
      if (r.status == RequestStatus.accepted ||
          r.status == RequestStatus.onTheWay ||
          r.status == RequestStatus.arrived ||
          r.status == RequestStatus.inProgress) {
        _sharer.start(r.id);
      } else {
        _sharer.stop();
      }
      _timer?.cancel();
      _radarAnim.stop();
      // Stop showing nearby providers once the search is over.
      _providersSub?.cancel();
      _providersSub = null;
      _providers = const [];
    } else {
      _providersSub ??= watchNearbyProviders(r.serviceType).listen((list) {
        if (mounted) setState(() => _providers = list);
      }, onError: (_) {});
    }

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

  /// Widens (or resets) the radius stored on the request so providers
  /// further away can see it.
  Future<void> _updateRadiusInFirestore(double km) async {
    try {
      await FirebaseFirestore.instance
          .collection(_requestsCollection)
          .doc(widget.requestId)
          .update({'searchRadiusKm': km});
    } catch (_) {
      // Non-fatal: the map still widens locally.
    }
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
        _stageRadiiKm.length - 1,
      );
      if (newStage != _stage) {
        setState(() => _stage = newStage);
        // Zoom out to show the wider search area and tell providers.
        _fitMapToRadius();
        _updateRadiusInFirestore(_currentRadiusKm);
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

  /// Providers that are inside the current search radius.
  List<NearbyProvider> _nearbyWithin(double radiusM) {
    const distance = Distance();
    return _providers.where((p) {
      final point = LatLng(p.location.latitude, p.location.longitude);
      return distance.as(LengthUnit.Meter, widget.pickup, point) <= radiusM;
    }).toList();
  }

  /// Called whenever the user touches the map. Restarts the 5 second wait.
  void _scheduleRecenter() {
    _recenterTimer?.cancel();
    _recenterTimer = Timer(_recenterDelay, () {
      if (mounted) _fitMapToRadius();
    });
  }

  void _fitMapToRadius() {
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: _radiusExtent(_currentRadiusKm),
        padding: _mapFitPadding,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Cancel request?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('We will stop looking for nearby assistance.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Keep searching',
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
    } catch (_) {}
    _leave();
  }

  Future<void> _onTryAgain() async {
    try {
      final renewed = await renewRequest(widget.requestId);
      if (!renewed || !mounted) return;
      setState(() => _stage = 0);
      // Start over from the smallest radius.
      _updateRadiusInFirestore(_currentRadiusKm);
      _fitMapToRadius();
      _startTimer();
      _radarAnim.repeat();
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
                        elevation: 4,
                        shadowColor: Colors.black38,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _onCancelPressed,
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

  // ---------------- Radar ----------------
  /// Soft filled rings that start at the pickup point and expand out to the
  /// edge of the search radius, fading as they grow.
  Widget _buildPulseRings(double radiusM) {
    return AnimatedBuilder(
      animation: _radarAnim,
      builder: (context, _) {
        final v = _radarAnim.value;

        return CircleLayer(
          circles: [
            for (final offset in const [0.0, 1 / 3, 2 / 3])
              () {
                final p = (v + offset) % 1;
                // Ease-out so the ring slows down near the edge.
                final eased = Curves.easeOut.transform(p);
                return CircleMarker(
                  point: widget.pickup,
                  radius: radiusM * eased,
                  useRadiusInMeter: true,
                  color: _brandRed.withValues(alpha: 0.10 * (1 - p)),
                  borderColor: _brandRed.withValues(alpha: 0.55 * (1 - p)),
                  borderStrokeWidth: 2,
                );
              }(),
          ],
        );
      },
    );
  }

  /// Rotating radar sweep: a wedge with a bright leading edge and a trail
  /// that fades out behind it.
  Widget _buildSweep(double radiusM) {
    const distance = Distance();
    const slices = 14;
    const sliceDeg = 3.0;

    return AnimatedBuilder(
      animation: _radarAnim,
      builder: (context, _) {
        final lead = _radarAnim.value * 360;
        LatLng at(double bearing) =>
            distance.offset(widget.pickup, radiusM, bearing);

        final polygons = <Polygon>[
          for (var i = 0; i < slices; i++)
            () {
              final start = lead - (i + 1) * sliceDeg;
              final end = lead - i * sliceDeg;
              return Polygon(
                points: [
                  widget.pickup,
                  at(start),
                  at((start + end) / 2),
                  at(end),
                ],
                color: _brandRed.withValues(alpha: 0.20 * (1 - i / slices)),
              );
            }(),
        ];

        return PolygonLayer(polygons: polygons);
      },
    );
  }

  Widget _buildSweepEdge(double radiusM) {
    const distance = Distance();

    return AnimatedBuilder(
      animation: _radarAnim,
      builder: (context, _) {
        final lead = _radarAnim.value * 360;
        return PolylineLayer(
          polylines: [
            Polyline(
              points: [
                widget.pickup,
                distance.offset(widget.pickup, radiusM, lead),
              ],
              strokeWidth: 2,
              color: _brandRed.withValues(alpha: 0.55),
            ),
          ],
        );
      },
    );
  }

  /// The customer's pickup point at the centre of the radar.
  Widget _buildPickupMarker() {
    return MarkerLayer(
      markers: [
        Marker(
          point: widget.pickup,
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _brandRed.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _brandRed,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 6),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 1.0 right when the radar sweep passes over the provider, fading to 0
  /// by the time it comes around again (like a real radar blip).
  double _blipOpacity(double leadDeg, LatLng point) {
    const distance = Distance();
    final bearing = (distance.bearing(widget.pickup, point) + 360) % 360;
    // Degrees since the sweep line passed over this provider.
    final since = (leadDeg - bearing + 360) % 360;
    return math.pow(1 - since / 360, 2).toDouble().clamp(0.0, 1.0);
  }

  Widget _buildProviderMarkers(double radiusM) {
    return AnimatedBuilder(
      animation: _radarAnim,
      builder: (context, _) {
        final lead = _radarAnim.value * 360;
        final nearby = _nearbyWithin(radiusM);

        NearbyProvider? selected;
        for (final p in nearby) {
          if (p.uid == _selectedUid) selected = p;
        }

        return MarkerLayer(
          markers: [
            for (final p in nearby)
              () {
                final point = LatLng(p.location.latitude, p.location.longitude);
                final isSelected = p.uid == _selectedUid;
                // Selected provider stays fully visible so its card is usable.
                final opacity = isSelected ? 1.0 : _blipOpacity(lead, point);
                return Marker(
                  key: ValueKey(p.uid),
                  point: point,
                  width: 30,
                  height: 30,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selectedUid = p.uid),
                    child: Opacity(
                      opacity: opacity,
                      child: Image.asset(
                        _assistanceIcon,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.local_shipping,
                          color: _brandRed,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                );
              }(),
            // Info card, added last so it draws on top. It sits just above the
            // tapped icon, like an info window on Google Maps.
            if (selected != null)
              Marker(
                key: ValueKey('card-${selected.uid}'),
                point: LatLng(
                  selected.location.latitude,
                  selected.location.longitude,
                ),
                width: 240,
                height: 130,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildProviderCard(selected.uid),
                    const SizedBox(height: 26), // clears the icon
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildProviderCard(String uid) {
    return GestureDetector(
      // Swallow taps so touching the card doesn't close it.
      onTap: () {},
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: FutureBuilder<AppUser?>(
          future: _providerDetails.putIfAbsent(uid, () => _loadProvider(uid)),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 44,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _brandRed,
                    ),
                  ),
                ),
              );
            }
            final user = snap.data;
            if (user == null) {
              return const SizedBox(
                height: 44,
                child: Center(child: Text('Details unavailable')),
              );
            }
            return _providerCardContent(user);
          },
        ),
      ),
    );
  }

  Widget _providerCardContent(AppUser user) {
    final fallbackAvatar = ColoredBox(
      color: Colors.grey.shade200,
      child: Icon(Icons.person_rounded, color: Colors.grey.shade500),
    );
    final hasPhoto = user.profileImagePath.isNotEmpty;
    final rating = user.rating;

    return Row(
      children: [
        ClipOval(
          child: SizedBox(
            width: 46,
            height: 46,
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
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.name.isEmpty ? 'Assistance' : user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: Colors.black87,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      rating.count > 0
                          ? '${rating.average.toStringAsFixed(1)} (${rating.count})'
                          : 'New provider',
                      style: const TextStyle(
                        fontSize: 11.5,
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
      ],
    );
  }

  Widget _buildMap() {
    final radiusKm = _currentRadiusKm;
    final radiusM = radiusKm * 1000;
    final searching = _status == RequestStatus.pending;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.pickup,
        initialZoom: 13,
        initialCameraFit: CameraFit.coordinates(
          coordinates: _radiusExtent(radiusKm),
          padding: _mapFitPadding,
        ),
        // Pinch to zoom and drag are allowed; rotation stays off.
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        // hasGesture is true only for finger input, so the automatic
        // recenter below doesn't trigger itself.
        onTap: (_, __) {
          if (_selectedUid != null) setState(() => _selectedUid = null);
        },
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) _scheduleRecenter();
        },
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
              radius: radiusM,
              useRadiusInMeter: true,
              color: _brandRed.withValues(alpha: 0.06),
              borderColor: _brandRed.withValues(alpha: 0.5),
              borderStrokeWidth: 1.5,
            ),
          ],
        ),
        // Radar: expanding rings + rotating sweep (only while searching).
        if (searching) _buildPulseRings(radiusM),
        if (searching) _buildSweep(radiusM),
        if (searching) _buildSweepEdge(radiusM),
        // Nearby assistance, live, only those inside the search radius.
        // Each icon blips in as the sweep passes and fades until the next pass.
        if (searching) _buildProviderMarkers(radiusM),
        // The customer's pickup point, always on top.
        _buildPickupMarker(),
      ],
    );
  }

  Widget _buildSheet() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        18,
        10,
        18,
        16 + MediaQuery.of(context).padding.bottom,
      ),
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
          const SizedBox(height: 18),
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
          color: Colors.grey.shade600,
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
    final radiusM = _currentRadiusKm * 1000;
    final count = _nearbyWithin(radiusM).length;
    final radiusLabel = _currentRadiusKm.toStringAsFixed(0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title + wait time
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Looking for nearby assistance',
                    style: TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.radar_rounded,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Searching within $radiusLabel km',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 14,
                    color: Colors.black87,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '~2 min',
                    style: TextStyle(
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
        const SizedBox(height: 18),
        _buildStageBars(),
        const SizedBox(height: 16),

        // Live status strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              _buildSearchAnimation(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Contacting providers nearby',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: count > 0 ? _success : Colors.grey.shade400,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            count == 0
                                ? 'Looking for available providers…'
                                : '$count available within $radiusLabel km',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: OutlinedButton(
            onPressed: _onCancelPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: _brandRed,
              backgroundColor: Colors.white,
              side: BorderSide(color: _brandRed.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text(
              'Cancel Request',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  /// Compact map image that gently pulses, with a magnifying glass sweeping
  /// around it in a circle.
  Widget _buildSearchAnimation() {
    const double size = 52;
    return SizedBox(
      width: size + 22,
      height: size + 22,
      child: AnimatedBuilder(
        animation: _searchAnim,
        builder: (context, _) {
          final t = _searchAnim.value * 2 * math.pi;
          final pulse = 1 + 0.04 * math.sin(t);
          final dx = math.cos(t) * 10;
          final dy = math.sin(t) * 7;

          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: pulse,
                // Rounded corners since the map image is a .jpg
                // (no transparency).
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    _searchMapImage,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.map_rounded,
                      size: size * 0.8,
                      color: Colors.green.shade300,
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(dx, dy),
                child: Transform.rotate(
                  angle: math.sin(t) * 0.12,
                  child: Image.asset(
                    _searchMagnifierImage,
                    width: size * 0.75,
                    height: size * 0.75,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.search_rounded,
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

  /// One bar per stage with its radius underneath. Past stages are full,
  /// the current one fills smoothly with elapsed time, future ones are empty.
  Widget _buildStageBars() {
    return ValueListenableBuilder<int>(
      valueListenable: _elapsedNotifier,
      builder: (context, elapsed, _) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _stageRadiiKm.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
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
    final done = index <= _stage;
    final current = index == _stage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 5,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: Colors.grey.shade200)),
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
        ),
        const SizedBox(height: 6),
        Text(
          '${_stageRadiiKm[index].toStringAsFixed(0)} km',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: current ? FontWeight.w800 : FontWeight.w500,
            color: done ? Colors.black87 : Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  // ---- Expired ----
  Widget _buildExpired() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusBadge(Icons.search_off_rounded, Colors.grey.shade600),
        const SizedBox(height: 14),
        const Text(
          'No assistance found nearby',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
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
          height: 50,
          child: OutlinedButton(
            onPressed: _leave,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text(
              'Close',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statusBadge(Icons.check_rounded, _success),
            const SizedBox(height: 14),
            const Text(
              'Assistance found!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$name accepted your request',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            if (rating != null && rating.count > 0) ...[
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
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
                        size: 16,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${rating.average.toStringAsFixed(1)} (${rating.count})',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusBadge(icon, color),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        _primaryButton('Close', _leave),
      ],
    );
  }

  /// Round, softly tinted icon badge used by the result states.
  Widget _statusBadge(IconData icon, Color color) {
    return Center(
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 34, color: color),
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback onPressed) {
    return SizedBox(
      height: 54,
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
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
