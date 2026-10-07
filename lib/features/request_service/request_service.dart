import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../entities/app_user.dart';
import '../../entities/service_request.dart'; // NearbyProvider, watchNearbyProviders, kSearchRadiiKm
import '../../entities/vehicle.dart';
import '../vehicles/add_vehicle_page.dart';
import 'request_summary_page.dart';

class _ServiceConfig {
  final String title;
  final String subtitle;
  final String iconPath;

  const _ServiceConfig({
    required this.title,
    required this.subtitle,
    required this.iconPath,
  });
}

const String _placeholderIcon = 'assets/images/pickup-point.png';
const String _pickupPinPath = 'assets/images/pickup-point.png';
const String _dropoffPinPath = 'assets/images/dropoff.png';

const Color _dropoffOrange = Color(0xFFFF8C00);

/// The search always starts at this radius. The searching page widens it
/// to 10 km and then 15 km if nobody accepts.
const double _initialSearchRadiusKm = 5.0;

String _iconAssetFor(VehicleType type) => switch (type) {
  VehicleType.car => 'assets/images/vehicle-car.png',
  VehicleType.van => 'assets/images/vehicle-van.png',
  VehicleType.motorbike => 'assets/images/vehicle-bike.png',
  VehicleType.threeWheeler => 'assets/images/vehicle-threewheel.png',
  VehicleType.truck => 'assets/images/vehicle-truck.png',
  VehicleType.bus => 'assets/images/vehicle-bus.png',
  VehicleType.towtruck => 'assets/images/vehicle-towtruck.png',
};

/// Vehicle-type image with a plain icon fallback if the asset is missing.
Widget _vehicleIcon(VehicleType type, {double size = 24}) {
  return Image.asset(
    _iconAssetFor(type),
    width: size,
    height: size,
    fit: BoxFit.contain,
    errorBuilder: (_, __, ___) => Icon(Icons.directions_car, size: size),
  );
}

/// Returned by the vehicle picker when "Add vehicle" is tapped.
const String _addVehicleResult = 'add_vehicle';

const int _minLiters = 1;
const int _maxLiters = 50;
const String _petrolIconPath = 'assets/images/icon-jerrycan.png';
const String _dieselIconPath = 'assets/images/gasoline1.png';

// Replace each iconPath manually later.
const Map<ServiceType, _ServiceConfig> _serviceConfigs = {
  ServiceType.towTruck: _ServiceConfig(
    title: 'Emergency Towing',
    subtitle: 'Transport your vehicle safely to a nearby garage or home',
    iconPath: _placeholderIcon,
  ),
  ServiceType.mechanic: _ServiceConfig(
    title: 'Request a Mechanic',
    subtitle: 'Get on-site inspection and roadside repairs',
    iconPath: _placeholderIcon,
  ),
  ServiceType.batteryBoost: _ServiceConfig(
    title: 'Request Battery Boosting',
    subtitle: 'Jump-Start',
    iconPath: _placeholderIcon,
  ),
  ServiceType.flatTireChange: _ServiceConfig(
    title: 'Request Flat Tire',
    subtitle: 'Airing it up or replace it with your spare',
    iconPath: _placeholderIcon,
  ),
  ServiceType.fuelDelivery: _ServiceConfig(
    title: 'Request Fuel Delivery',
    subtitle: 'Get emergency fuel delivered directly to your location',
    iconPath: _placeholderIcon,
  ),
};

// ---------------------------------------------------------------------------
// Free map services (no API key / billing)
//  - Tiles:     OpenStreetMap
//  - Geocoding: Nominatim (max 1 request/second, no autocomplete)
//  - Routing:   OSRM public demo server (testing only, not for production)
// ---------------------------------------------------------------------------

/// Nominatim requires an identifying User-Agent. Put your real contact here.
const String _userAgent = 'RoadsideAssistance/1.0 (kavidupurnamal@gmail.com)';

const String _appPackageName = 'com.example.roadside_assitance';

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

class MapApi {
  static Future<LatLng?> geocode(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '1',
        'countrycodes': 'lk', // restrict to Sri Lanka; remove if not needed
      });
      final res = await http.get(uri, headers: {'User-Agent': _userAgent});
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body) as List;
      if (list.isEmpty) return null;
      return LatLng(
        double.parse(list[0]['lat'] as String),
        double.parse(list[0]['lon'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String?> reverseGeocode(LatLng p) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': '${p.latitude}',
        'lon': '${p.longitude}',
        'format': 'jsonv2',
      });
      final res = await http.get(uri, headers: {'User-Agent': _userAgent});
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['display_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<RouteResult?> route(LatLng a, LatLng b) async {
    try {
      // OSRM expects longitude,latitude order.
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
      return RouteResult(
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
}

enum _PickTarget { pickup, dropoff }

enum _FuelType { petrol, diesel }

/// Where the user is in the flow:
///  pickingPickup  -> pin in the middle of the map, "Confirm pickup point"
///  pickingDropoff -> same, for the drop-off (tow truck only)
///  details        -> normal sheet (vehicle, fuel, fields) + "Confirm"
enum _Phase { pickingPickup, pickingDropoff, details }

class RequestServicePage extends StatefulWidget {
  final ServiceType serviceType;
  final UserType userType;

  const RequestServicePage({
    super.key,
    required this.serviceType,
    this.userType = UserType.driver,
  });

  @override
  State<RequestServicePage> createState() => _RequestServicePageState();
}

class _RequestServicePageState extends State<RequestServicePage>
    with WidgetsBindingObserver {
  static const Color _brandRed = Color(0xFFE30613);

  // How far the map extends under the sheet so its rounded corners
  // don't show a white gap.
  static const double _mapUnderlap = 30;

  // Centre pin size / how far it lifts while the map is being moved.
  static const double _pinW = 44;
  static const double _pinH = 54;
  static const double _pinLift = 18;

  // Malabe fallback until live location is available.
  static final LatLng _initialCenter = LatLng(6.9061, 79.9697);

  final _mapController = MapController();
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();

  _Phase _phase = _Phase.pickingPickup;
  _PickTarget _activeField = _PickTarget.pickup;

  /// True once the user has confirmed all required points at least once.
  /// From then on "back" while re-picking returns to the details sheet.
  bool _reachedDetails = false;

  bool _mapReady = false;
  bool _userTouchedMap = false;

  /// True while the user is dragging/flinging the map (pin lifted, dot shown).
  /// A notifier so only the pin / confirm button rebuild, not the whole page.
  final ValueNotifier<bool> _moving = ValueNotifier<bool>(false);
  Timer? _settleTimer;

  /// Point under the centre pin once the map has stopped, and its address.
  LatLng? _pendingPoint;
  String? _pendingAddress;
  int _pendingToken = 0;

  LatLng? _pickup;
  LatLng? _dropoff;
  List<LatLng> _routePoints = [];
  double? _distanceKm;
  int? _durationMin;
  bool _loadingRoute = false;

  // Live user location
  LatLng? _userLocation;
  double _userAccuracy = 0;
  double? _heading; // degrees clockwise from north; last known while moving
  bool _locatingUser = true;
  bool _hasCenteredOnUser = false;
  StreamSubscription<Position>? _positionSub;
  bool _trackingActive = false;

  // Fuel delivery options
  int _liters = 5; // last valid value
  _FuelType _fuelType = _FuelType.petrol;
  final _litersController = TextEditingController(text: '5');
  final _litersFocus = FocusNode();

  // Vehicle for this request (user's active vehicle by default)
  Vehicle? _vehicle;
  bool _loadingVehicle = true;
  bool _dialogShowing = false;

  _ServiceConfig get _config => _serviceConfigs[widget.serviceType]!;

  bool get _isTow => widget.serviceType == ServiceType.towTruck;
  bool get _isMechanic => widget.serviceType == ServiceType.mechanic;

  bool get _isFlatTire => widget.serviceType == ServiceType.flatTireChange;
  bool get _isBattery => widget.serviceType == ServiceType.batteryBoost;

  bool get _isFuel => widget.serviceType == ServiceType.fuelDelivery;

  /// Services with a single location (no drop-off).
  bool get _isSingleLocation =>
      _isMechanic || _isFlatTire || _isBattery || _isFuel;

  /// Services that show the vehicle button.
  bool get _usesVehicle => _isTow || _isMechanic;

  bool get _isPicking => _phase != _Phase.details;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadActiveVehicle();
    // When the amount field loses focus, restore a valid value if it's
    // empty or 0.
    _litersFocus.addListener(() {
      if (!_litersFocus.hasFocus) {
        final n = int.tryParse(_litersController.text);
        if (n == null || n < _minLiters) _setLiters(_liters);
      }
    });
  }

  /// When the user comes back from the system settings after turning
  /// location on, start tracking automatically.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed) return;
    if (_trackingActive || _userLocation != null) return;
    if (!await Geolocator.isLocationServiceEnabled()) return;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) return;
    if (!mounted) return;
    setState(() => _locatingUser = true);
    _startLocationTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settleTimer?.cancel();
    _moving.dispose();
    _litersController.dispose();
    _litersFocus.dispose();
    _positionSub?.cancel();
    _mapController.dispose();
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    // Back leaves the page only from the first pickup step or the details
    // sheet; in between it steps back through the flow.
    final canPop =
        _phase == _Phase.details ||
        (_phase == _Phase.pickingPickup && !_reachedDetails);

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Map runs slightly under the sheet (paints beneath it).
                  // The centre pin lives in the same box so it sits exactly
                  // on the map's centre.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: -_mapUnderlap,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildMap(),
                        if (_isPicking) _buildCenterPin(),
                      ],
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, top: 8),
                      child: _circleButton(
                        icon: Icons.chevron_left,
                        onTap: _onBack,
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
                  Positioned(
                    right: 16,
                    bottom: 16 + _mapUnderlap,
                    child: _circleButton(
                      icon: Icons.my_location,
                      size: 52,
                      onTap: _goToMyLocation,
                    ),
                  ),
                  if (_locatingUser) _buildLocatingOverlay(),
                ],
              ),
            ),
            _isPicking ? _buildPickBar() : _buildSheet(),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _initialCenter,
        initialZoom: 15,
        // Rotation stays off so the heading cone always points correctly.
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          _mapReady = true;
          _startLocationTracking();
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _updatePendingFromCenter(),
          );
        },
        onPositionChanged: (camera, hasGesture) =>
            _onMapPositionChanged(hasGesture),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _appPackageName,
        ),
        // GPS accuracy circle (only while choosing a point)
        if (_isPicking && _userLocation != null && _userAccuracy > 0)
          CircleLayer(
            circles: [
              CircleMarker(
                point: _userLocation!,
                radius: _userAccuracy,
                useRadiusInMeter: true,
                color: Colors.blue.withValues(alpha: 0.12),
                borderColor: Colors.blue.withValues(alpha: 0.4),
                borderStrokeWidth: 1,
              ),
            ],
          ),
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
        // rotate: true keeps the markers upright.
        MarkerLayer(
          rotate: true,
          markers: [
            // Live user location: blue dot with a cone showing the direction
            // they are facing (same as the tracking page). Drawn first so the
            // pins sit on top.
            if (_userLocation != null)
              Marker(
                point: _userLocation!,
                width: 64,
                height: 64,
                child: _HeadingDot(heading: _heading),
              ),
            // Confirmed points. The one currently being picked is hidden:
            // the centre pin stands in for it.
            if (_pickup != null && _phase != _Phase.pickingPickup)
              _dotMarker(
                point: _pickup!,
                // Towing shows Pickup; every other service has a single
                // point shown as "Delivery". Both are red.
                tag: _isTow ? 'Pickup' : 'Delivery',
                tagColor: _brandRed,
                dotColor: _brandRed,
                address: _pickupController.text,
                onTap: () => _startRepick(_PickTarget.pickup),
              ),
            if (_dropoff != null && _phase != _Phase.pickingDropoff)
              _dotMarker(
                point: _dropoff!,
                tag: 'Drop',
                tagColor: _dropoffOrange,
                dotColor: _dropoffOrange,
                address: _dropoffController.text,
                onTap: () => _startRepick(_PickTarget.dropoff),
              ),
          ],
        ),
      ],
    );
  }

  /// Confirmed point: a plain dot (black for pickup, red for drop-off) centred
  /// on the exact coordinate, with the address pill floating above it.
  /// The pin images are only used while choosing a point. Tapping the dot
  /// goes back to re-pick that point.
  Marker _dotMarker({
    required LatLng point,
    required String tag,
    required Color tagColor,
    required Color dotColor,
    required String address,
    required VoidCallback onTap,
  }) {
    return Marker(
      point: point,
      width: 250,
      height: 120,
      child: _LabeledDot(
        pill: _AddressPill(
          tag: tag,
          color: tagColor,
          text: address.isEmpty ? '$tag point' : address,
        ),
        color: dotColor,
        onTap: onTap,
      ),
    );
  }

  /// Pin fixed in the middle of the map while choosing a point.
  /// - Map moving: pin lifts up and a small dot marks the exact spot below it.
  /// - Map stopped: the dot disappears and the pin drops onto that spot.
  Widget _buildCenterPin() {
    final isDrop = _phase == _Phase.pickingDropoff;
    final asset = isDrop ? _dropoffPinPath : _pickupPinPath;
    final fallbackColor = isDrop ? _brandRed : Colors.green;

    return IgnorePointer(
      child: Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: _moving,
          builder: (context, moving, _) {
            // Zero-height anchor sitting exactly on the map centre; children
            // are positioned relative to it (negative top = above centre).
            return SizedBox(
              width: _pinW,
              height: 0,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: _pinW / 2 - 5,
                    top: -5,
                    child: AnimatedOpacity(
                      opacity: moving ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          // Red for pickup / location, orange for drop-off.
                          color: isDrop ? _dropoffOrange : _brandRed,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    left: 0,
                    top: -_pinH - (moving ? _pinLift : 0),
                    width: _pinW,
                    height: _pinH,
                    child: Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.location_on,
                        color: fallbackColor,
                        size: _pinH * 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLocatingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.white.withValues(alpha: 0.6),
        alignment: Alignment.center,
        child: Material(
          color: Colors.white,
          elevation: 4,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: _brandRed),
                SizedBox(height: 12),
                Text('Getting your location…'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 40,
  }) {
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

  BoxDecoration _sheetDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 15,
          offset: const Offset(0, -3),
        ),
      ],
    );
  }

  Widget _grabber() {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  // ---------------- Pick bar (choose a point with the centre pin) --------
  Widget _buildPickBar() {
    final isDrop = _phase == _Phase.pickingDropoff;
    final String title;
    final String hint;
    final String confirmLabel;
    if (_isSingleLocation) {
      title = 'Set your location';
      hint = 'Move the map to place the pin on your location';
      confirmLabel = 'Confirm location';
    } else if (isDrop) {
      title = 'Set drop-off point';
      hint = 'Move the map to place the pin on the drop-off point';
      confirmLabel = 'Confirm drop-off point';
    } else {
      title = 'Set pickup point';
      hint = 'Move the map to place the pin on the pickup point';
      confirmLabel = 'Confirm pickup point';
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: _sheetDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grabber(),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<bool>(
            valueListenable: _moving,
            builder: (context, moving, _) {
              final address = moving
                  ? 'Locating…'
                  : (_pendingAddress ?? 'Finding address…');
              final enabled = !moving && _pendingPoint != null;
              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: Row(
                      children: [
                        Image.asset(
                          isDrop ? _dropoffPinPath : _pickupPinPath,
                          width: 24,
                          height: 24,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.location_on_outlined,
                            size: 24,
                            color: isDrop ? _brandRed : Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            address,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: (moving || _pendingAddress == null)
                                  ? Colors.grey.shade600
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: enabled ? _onConfirmPoint : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brandRed,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _brandRed.withValues(
                          alpha: 0.4,
                        ),
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------- Details sheet ----------------
  Widget _buildSheet() {
    return ConstrainedBox(
      // Keeps the map visible even on small screens / with the keyboard open.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: _sheetDecoration(),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _grabber(),
              const SizedBox(height: 14),
              Text(
                _config.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _config.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              _buildServiceDetails(),
              const SizedBox(height: 20),
              _buildConfirmButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// Each service gets its own details UI here.
  Widget _buildServiceDetails() {
    switch (widget.serviceType) {
      case ServiceType.towTruck:
        return _buildTowingDetails();
      case ServiceType.mechanic:
        return _buildSingleLocationDetails(showVehicle: true);
      case ServiceType.flatTireChange:
      case ServiceType.batteryBoost:
        return _buildSingleLocationDetails(showVehicle: false);
      case ServiceType.fuelDelivery:
        return _buildSingleLocationDetails(
          showVehicle: false,
          hint: 'Enter Delivery Location',
          header: _buildFuelOptions(),
        );
    }
  }

  // ---------------- Towing ----------------
  Widget _buildTowingDetails() {
    return Column(
      children: [
        // Vehicle on the left, distance + time on the same level on the right.
        Row(
          children: [
            Flexible(child: _buildVehicleButton()),
            const SizedBox(width: 12),
            Expanded(child: _buildRouteSummary()),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: Row(
            children: [
              Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _startRepick(_PickTarget.pickup),
                    child: Image.asset(
                      _config.iconPath,
                      width: 24,
                      height: 24,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.local_shipping_outlined, size: 24),
                    ),
                  ),
                  ...List.generate(
                    4,
                    (_) => Container(
                      width: 1.5,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: Colors.black87,
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _startRepick(_PickTarget.dropoff),
                    child: Image.asset(
                      _dropoffPinPath,
                      width: 24,
                      height: 24,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.location_on_outlined, size: 24),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _locationField(
                      _pickupController,
                      'Enter Pickup Location',
                      _PickTarget.pickup,
                    ),
                    Divider(height: 1, color: Colors.grey.shade400),
                    _locationField(
                      _dropoffController,
                      'Enter Drop-off Location',
                      _PickTarget.dropoff,
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

  // ------- Single-location services (mechanic, flat tire, battery) -------
  Widget _buildSingleLocationDetails({
    required bool showVehicle,
    String hint = 'Enter Your Location',
    Widget? header,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showVehicle) ...[
          Align(alignment: Alignment.centerLeft, child: _buildVehicleButton()),
          const SizedBox(height: 18),
        ],
        if (header != null) header,
        const Text(
          'Location',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _startRepick(_PickTarget.pickup),
                child: const Icon(Icons.location_on_outlined, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _locationField(
                  _pickupController,
                  hint,
                  _PickTarget.pickup,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleButton() {
    final Widget content;
    if (_loadingVehicle) {
      content = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Loading vehicle…',
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ],
      );
    } else if (_vehicle != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _vehicleIcon(_vehicle!.vehicleType, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _vehicle!.displayLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black87, fontSize: 14),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.keyboard_arrow_down,
            size: 18,
            color: Colors.black54,
          ),
        ],
      );
    } else {
      content = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, size: 18, color: Colors.black54),
          SizedBox(width: 8),
          Text(
            'Add vehicle',
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ],
      );
    }

    return OutlinedButton(
      onPressed: _loadingVehicle ? null : _onVehicleButtonTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: content,
    );
  }

  Widget _buildRouteSummary() {
    if (_loadingRoute) {
      return const Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_distanceKm == null || _durationMin == null) {
      return const SizedBox.shrink();
    }
    return Text(
      '${_distanceKm!.toStringAsFixed(1)} km · $_durationMin min',
      textAlign: TextAlign.right,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }

  /// Read-only: tapping the field opens the map picker for that point.
  Widget _locationField(
    TextEditingController controller,
    String hint,
    _PickTarget target,
  ) {
    return TextField(
      controller: controller,
      readOnly: true,
      showCursor: false,
      enableInteractiveSelection: false,
      style: const TextStyle(fontSize: 14),
      onTap: () => _startRepick(target),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  // ---------------- Fuel delivery ----------------
  Widget _buildFuelOptions() {
    const labelStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Fuel Amount', style: labelStyle),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: _pillDecoration(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 36),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 18),
                onPressed: _liters > _minLiters
                    ? () => _setLiters(_liters - 1)
                    : null,
              ),
              const Text(
                'Liters',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 2),
              SizedBox(
                width: 26,
                child: TextField(
                  controller: _litersController,
                  focusNode: _litersFocus,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  onChanged: _onLitersChanged,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 36),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 18),
                onPressed: _liters < _maxLiters
                    ? () => _setLiters(_liters + 1)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text('Fuel Type', style: labelStyle),
        const SizedBox(height: 10),
        Row(
          children: [
            _fuelChip(_FuelType.petrol, 'Petrol', _petrolIconPath),
            const SizedBox(width: 12),
            _fuelChip(_FuelType.diesel, 'Diesel', _dieselIconPath),
          ],
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  void _setLiters(int n) {
    setState(() => _liters = n);
    _litersController.value = TextEditingValue(
      text: '$n',
      selection: TextSelection.collapsed(offset: '$n'.length),
    );
  }

  void _onLitersChanged(String text) {
    final n = int.tryParse(text);
    if (n == null) return; // empty while typing
    if (n > _maxLiters) {
      _setLiters(_maxLiters);
      _snack('Maximum is $_maxLiters liters');
      return;
    }
    if (n >= _minLiters) setState(() => _liters = n);
  }

  BoxDecoration _pillDecoration({Color color = Colors.white}) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _fuelChip(_FuelType type, String label, String iconPath) {
    final selected = _fuelType == type;
    return GestureDetector(
      onTap: () => setState(() => _fuelType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: _pillDecoration(
          color: selected ? Colors.black : Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tinted to match the selected / unselected state.
            Image.asset(
              iconPath,
              width: 22,
              height: 22,
              fit: BoxFit.contain,
              color: selected ? Colors.white : Colors.black87,
              errorBuilder: (_, __, ___) => Icon(
                Icons.local_gas_station,
                size: 22,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Shared ----------------
  Widget _buildConfirmButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _onConfirm,
        style: ElevatedButton.styleFrom(
          backgroundColor: _brandRed,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: const Text(
          'Confirm',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // ---------------- Location helpers ----------------
  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _coordsText(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

  Future<void> _showLocationAlert({
    required String title,
    required String message,
    required String actionLabel,
    required Future<void> Function() onAction,
  }) async {
    if (!mounted || _dialogShowing) return;
    _dialogShowing = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onAction();
            },
            child: Text(actionLabel, style: const TextStyle(color: _brandRed)),
          ),
        ],
      ),
    );
    _dialogShowing = false;
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await _showLocationAlert(
        title: 'Location is turned off',
        message:
            'Please turn on location services so we can find where you are.',
        actionLabel: 'Turn On',
        onAction: () async {
          await Geolocator.openLocationSettings();
        },
      );
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      await _showLocationAlert(
        title: 'Location permission needed',
        message: 'Location access is blocked for this app. Enable it in the app settings.',
        actionLabel: 'Open Settings',
        onAction: () async {
          await Geolocator.openAppSettings();
        },
      );
      return false;
    }
    if (permission == LocationPermission.denied) {
      _snack('Location permission denied');
      return false;
    }
    return true;
  }

  Future<LatLng?> _getCurrentLatLng() async {
    try {
      if (!await _ensureLocationPermission()) return null;
      final pos = await Geolocator.getCurrentPosition();
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      _snack('Could not get your location');
      return null;
    }
  }

  Future<void> _goToMyLocation() async {
    final here = _userLocation ?? await _getCurrentLatLng();
    if (here == null || !mounted) return;
    _mapController.move(here, 17);
  }

  /// Runs once the map is ready: gets a first fix, then streams live updates.
  Future<void> _startLocationTracking() async {
    if (_trackingActive) return;
    _trackingActive = true;
    try {
      if (!await _ensureLocationPermission()) {
        _trackingActive = false;
        if (mounted) setState(() => _locatingUser = false);
        return;
      }

      // Fast first fix so the spinner goes away quickly.
      try {
        final first = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
        _onPosition(first);
      } catch (_) {
        // Fall through; the stream below may still deliver a fix.
      }

      if (!mounted) return;

      // Live updates.
      _positionSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5, // metres moved before a new update
            ),
          ).listen(
            _onPosition,
            onError: (_) {
              if (mounted) setState(() => _locatingUser = false);
            },
          );

      // Stop the spinner even if no fix ever arrives.
      Future.delayed(const Duration(seconds: 20), () {
        if (mounted && _locatingUser) {
          setState(() => _locatingUser = false);
          _snack('Could not get your location');
        }
      });
    } catch (_) {
      _trackingActive = false;
      if (mounted) setState(() => _locatingUser = false);
    }
  }

  void _onPosition(Position pos) {
    if (!mounted) return;
    final here = LatLng(pos.latitude, pos.longitude);
    final isFirstFix = !_hasCenteredOnUser;

    setState(() {
      _userLocation = here;
      _userAccuracy = pos.accuracy;
      _locatingUser = false;
      // GPS heading is only meaningful while moving; otherwise keep the
      // last known direction.
      if (pos.heading.isFinite && pos.heading >= 0 && pos.speed > 0.5) {
        _heading = pos.heading;
      }
    });

    if (isFirstFix) {
      _hasCenteredOnUser = true;
      // Pickup is NOT filled automatically any more: just bring the map to
      // the user so they can place the pin where they want.
      if (_phase == _Phase.pickingPickup &&
          _pickup == null &&
          !_userTouchedMap) {
        _mapController.move(here, 17);
      }
    }
  }

  // ---------------- Centre-pin picking ----------------
  /// Called on every camera change. While the user drags, the pin is lifted;
  /// once the map has been still for a moment it "settles".
  void _onMapPositionChanged(bool hasGesture) {
    if (!_isPicking) return;
    if (hasGesture) {
      _userTouchedMap = true;
      if (!_moving.value) _moving.value = true;
    }
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 350), _onMapSettled);
  }

  void _onMapSettled() {
    if (!mounted || !_isPicking || !_mapReady) return;
    _moving.value = false;
    final c = _mapController.camera.center;
    final p = _pendingPoint;
    // Already resolved for this exact spot (avoids a duplicate lookup).
    if (p != null &&
        (p.latitude - c.latitude).abs() < 1e-7 &&
        (p.longitude - c.longitude).abs() < 1e-7) {
      return;
    }
    _updatePendingFromCenter();
  }

  /// Reads the point under the centre pin and looks up its address.
  Future<void> _updatePendingFromCenter() async {
    if (!mounted || !_mapReady || !_isPicking) return;
    final center = _mapController.camera.center;
    final token = ++_pendingToken;
    setState(() {
      _pendingPoint = center;
      _pendingAddress = null;
    });
    final address = await MapApi.reverseGeocode(center);
    if (!mounted || token != _pendingToken) return; // user moved again
    setState(() => _pendingAddress = address ?? _coordsText(center));
  }

  /// Moves to a phase of the flow. [moveTo] recentres the map first.
  void _goToPhase(_Phase phase, {LatLng? moveTo}) {
    FocusScope.of(context).unfocus();
    _settleTimer?.cancel();
    _moving.value = false;
    _pendingToken++;
    setState(() {
      _phase = phase;
      if (phase == _Phase.pickingPickup) _activeField = _PickTarget.pickup;
      if (phase == _Phase.pickingDropoff) _activeField = _PickTarget.dropoff;
      _pendingPoint = null;
      _pendingAddress = null;
    });
    if (moveTo != null && _mapReady) _mapController.move(moveTo, 17);
    if (phase != _Phase.details) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _updatePendingFromCenter(),
      );
    }
  }

  /// "Confirm pickup / drop-off point" button.
  Future<void> _onConfirmPoint() async {
    final point = _pendingPoint;
    if (point == null) return;

    final target = _phase == _Phase.pickingDropoff
        ? _PickTarget.dropoff
        : _PickTarget.pickup;
    final address = _pendingAddress; // null -> _setPoint looks it up

    // Towing: after the pickup, go on to choose the drop-off the same way.
    final next = (_isTow && target == _PickTarget.pickup && _dropoff == null)
        ? _Phase.pickingDropoff
        : _Phase.details;
    if (next == _Phase.details) _reachedDetails = true;

    _goToPhase(next);
    await _setPoint(target, point, label: address);
  }

  /// Back arrow: steps back through the flow, or leaves the page.
  void _onBack() {
    if (_phase == _Phase.details) {
      Navigator.of(context).pop();
      return;
    }
    if (_reachedDetails) {
      // Cancel a re-pick and return to the details sheet.
      _settleTimer?.cancel();
      _moving.value = false;
      setState(() => _phase = _Phase.details);
      return;
    }
    if (_phase == _Phase.pickingDropoff) {
      _goToPhase(_Phase.pickingPickup, moveTo: _pickup);
      return;
    }
    Navigator.of(context).pop();
  }

  /// Stores a point, updates its text field, then refreshes the route.
  /// If [label] is null the address is looked up from the coordinates.
  Future<void> _setPoint(
    _PickTarget target,
    LatLng point, {
    String? label,
  }) async {
    final controller = target == _PickTarget.pickup
        ? _pickupController
        : _dropoffController;

    controller.text = label ?? _coordsText(point);
    setState(() {
      if (target == _PickTarget.pickup) {
        _pickup = point;
      } else {
        _dropoff = point;
      }
    });

    if (label == null) {
      final address = await MapApi.reverseGeocode(point);
      if (!mounted) return;
      if (address != null) {
        controller.text = address;
        setState(() {});
      }
    }

    await _updateRoute();
  }

  Future<void> _updateRoute() async {
    final a = _pickup;
    final b = _dropoff;
    if (a == null || b == null) return;

    setState(() => _loadingRoute = true);
    final result = await MapApi.route(a, b);
    if (!mounted) return;

    if (result == null) {
      setState(() {
        _loadingRoute = false;
        _routePoints = [];
        _distanceKm = null;
        _durationMin = null;
      });
      _snack('Could not find a route between these locations');
      return;
    }

    setState(() {
      _loadingRoute = false;
      _routePoints = result.points;
      _distanceKm = result.distanceMeters / 1000;
      _durationMin = (result.durationSeconds / 60).round();
    });

    // Don't fight the user while they are choosing a point.
    if (_isPicking) return;

    // The map now sits above the sheet, so only small paddings are needed.
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: result.points,
        padding: const EdgeInsets.fromLTRB(50, 100, 50, 80),
      ),
    );
  }

  // ---------------- Actions ----------------
  /// Called when a pin (map or sheet icon) is tapped: go back to choosing
  /// that point with the centre pin, starting from where it is now.
  void _startRepick(_PickTarget target) {
    final existing = target == _PickTarget.pickup ? _pickup : _dropoff;
    _goToPhase(
      target == _PickTarget.pickup
          ? _Phase.pickingPickup
          : _Phase.pickingDropoff,
      moveTo: existing,
    );
  }

  /// Loads the logged-in user's active vehicle (if any) on page load.
  Future<void> _loadActiveVehicle() async {
    if (!_usesVehicle) {
      _loadingVehicle = false;
      return;
    }
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // NOTE: assumes users are stored in the top-level `users` collection.
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data == null) return;

      final user = userFromMap(uid, data);
      final vehicle = await fetchActiveVehicle(user);
      if (!mounted) return;
      setState(() => _vehicle = vehicle);
    } catch (_) {
      // Leave the button in its "Add Car" state.
    } finally {
      if (mounted) setState(() => _loadingVehicle = false);
    }
  }

  /// Tapping the vehicle button lets the user pick another of their vehicles.
  Future<void> _onVehicleButtonTap() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _snack('Please log in first');
      return;
    }

    List<Vehicle> vehicles;
    try {
      vehicles = await fetchVehiclesForUser(uid);
    } catch (_) {
      _snack('Could not load your vehicles');
      return;
    }
    if (!mounted) return;

    final picked = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Select your vehicle',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final v in vehicles)
                    ListTile(
                      leading: _vehicleIcon(v.vehicleType, size: 32),
                      title: Text('${v.make} ${v.model}'.trim()),
                      subtitle: Text(v.plateNumber),
                      trailing: v.id == _vehicle?.id
                          ? const Icon(Icons.check_circle, color: _brandRed)
                          : null,
                      onTap: () => Navigator.of(ctx).pop(v),
                    ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const CircleAvatar(
                      radius: 16,
                      backgroundColor: _brandRed,
                      child: Icon(Icons.add, size: 20, color: Colors.white),
                    ),
                    title: const Text('Add vehicle'),
                    onTap: () => Navigator.of(ctx).pop(_addVehicleResult),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || picked == null) return;
    if (picked is Vehicle) {
      setState(() => _vehicle = picked);
    } else if (picked == _addVehicleResult) {
      final added = await Navigator.of(context).push<Vehicle>(
        MaterialPageRoute(builder: (_) => AddVehiclePage(ownerUid: uid)),
      );
      // AddVehiclePage pops with the saved Vehicle on Confirm.
      if (added != null && mounted) setState(() => _vehicle = added);
    }
  }

  void _onConfirm() {
    if (_isTow && (_pickup == null || _dropoff == null)) {
      _snack('Please set both pickup and drop-off locations');
      return;
    }
    if (_isSingleLocation && _pickup == null) {
      _snack('Please set your location');
      return;
    }
    if (_isFuel) {
      final n = int.tryParse(_litersController.text);
      if (n == null || n < _minLiters || n > _maxLiters) {
        _snack(
          'Enter a fuel amount between $_minLiters and $_maxLiters liters',
        );
        return;
      }
    }
    // The request starts at the default radius (5 km); the searching page
    // widens it to 10 km and 15 km automatically.
    if (_isTow) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RequestSummaryPage(
            serviceType: widget.serviceType,
            pickupAddress: _pickupController.text,
            dropoffAddress: _dropoffController.text,
            pickup: _pickup!,
            dropoff: _dropoff!,
            routePoints: _routePoints,
            distanceKm: _distanceKm,
            durationMin: _durationMin,
            vehicle: _vehicle,
            searchRadiusKm: _initialSearchRadiusKm,
          ),
        ),
      );
      return;
    }
    if (_isSingleLocation) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RequestSummaryPage(
            serviceType: widget.serviceType,
            pickupAddress: _pickupController.text,
            pickup: _pickup!,
            vehicle: _isMechanic ? _vehicle : null,
            liters: _isFuel ? int.parse(_litersController.text) : null,
            fuelType: _isFuel
                ? (_fuelType == _FuelType.petrol ? 'Petrol' : 'Diesel')
                : null,
            searchRadiusKm: _initialSearchRadiusKm,
          ),
        ),
      );
      return;
    }
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

/// Label pill above a ring-style dot (solid colour with a white centre).
/// The marker is centred on the map point and the dot is centred inside the
/// marker, so the dot's middle sits exactly on the location.
class _LabeledDot extends StatelessWidget {
  final Widget pill;
  final Color color;
  final VoidCallback? onTap;

  const _LabeledDot({required this.pill, required this.color, this.onTap});

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
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
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
