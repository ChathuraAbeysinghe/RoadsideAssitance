import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../entities/app_user.dart';

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

const String _placeholderIcon = 'assets/images/icon-towtruck.png';
const String _pickupPinPath = 'assets/images/pickup-point.png';

// Replace each iconPath manually later.
const Map<ServiceType, _ServiceConfig> _serviceConfigs = {
  ServiceType.towTruck: _ServiceConfig(
    title: 'Emergency Towing',
    subtitle: 'Transport your vehicle safely to a nearby garage or home',
    iconPath: _placeholderIcon,
  ),
  ServiceType.mechanic: _ServiceConfig(
    title: 'Request Mechanic',
    subtitle: 'A mechanic will come to your location',
    iconPath: _placeholderIcon,
  ),
  ServiceType.batteryBoost: _ServiceConfig(
    title: 'Jump Start',
    subtitle: 'Get your dead battery started again',
    iconPath: _placeholderIcon,
  ),
  ServiceType.flatTireChange: _ServiceConfig(
    title: 'Flat Tire',
    subtitle: 'Get your flat tire changed on the spot',
    iconPath: _placeholderIcon,
  ),
  ServiceType.fuelDelivery: _ServiceConfig(
    title: 'Fuel Delivery',
    subtitle: 'Fuel delivered to wherever you are stuck',
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

class _MapApi {
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

  static Future<_RouteResult?> route(LatLng a, LatLng b) async {
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
}

enum _PickTarget { pickup, dropoff }

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

class _RequestServicePageState extends State<RequestServicePage> {
  static const Color _brandRed = Color(0xFFE30613);

  // How far the map extends under the sheet so its rounded corners
  // don't show a white gap.
  static const double _mapUnderlap = 30;

  // Malabe fallback until live location is available.
  static final LatLng _initialCenter = LatLng(6.9061, 79.9697);

  final _mapController = MapController();
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();

  _PickTarget _activeField = _PickTarget.pickup;
  bool _pickingOnMap = false;

  LatLng? _pickup;
  LatLng? _dropoff;
  List<LatLng> _routePoints = [];
  double? _distanceKm;
  int? _durationMin;
  bool _loadingRoute = false;

  // Live user location
  LatLng? _userLocation;
  double _userAccuracy = 0;
  bool _locatingUser = true;
  bool _hasCenteredOnUser = false;
  StreamSubscription<Position>? _positionSub;

  _ServiceConfig get _config => _serviceConfigs[widget.serviceType]!;

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController.dispose();
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Map area: top part of the screen, or full screen while picking.
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Map runs slightly under the sheet (paints beneath it).
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: -_mapUnderlap,
                  child: _buildMap(),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, top: 8),
                    child: _circleButton(
                      icon: Icons.chevron_left,
                      onTap: () => Navigator.of(context).pop(),
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
                if (_pickingOnMap) _buildPickingBanner(),
                Positioned(
                  right: 16,
                  bottom: _pickingOnMap ? 24 + bottomInset : 16 + _mapUnderlap,
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
          // Hide the sheet while picking so the whole map is visible.
          if (!_pickingOnMap) _buildSheet(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _initialCenter,
        initialZoom: 15,
        onMapReady: _startLocationTracking,
        onTap: (_, point) => _onMapTap(point),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _appPackageName,
        ),
        // GPS accuracy circle
        if (_userLocation != null && _userAccuracy > 0)
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
        // rotate: true keeps the pins upright when the map is rotated.
        MarkerLayer(
          rotate: true,
          markers: [
            // Live user location (blue dot), drawn first so pins sit on top.
            if (_userLocation != null)
              Marker(
                point: _userLocation!,
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
            if (_pickup != null)
              Marker(
                point: _pickup!,
                width: 40,
                height: 48,
                // Pin tip sits on the exact coordinate.
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _startRepick(_PickTarget.pickup),
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
              ),
            if (_dropoff != null)
              Marker(
                point: _dropoff!,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _startRepick(_PickTarget.dropoff),
                  child: const Icon(
                    Icons.location_on,
                    color: Color.fromARGB(255, 0, 0, 0),
                    size: 40,
                  ),
                ),
              ),
          ],
        ),
      ],
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

  Widget _buildPickingBanner() {
    final label = _activeField == _PickTarget.pickup ? 'pickup' : 'drop-off';
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
          child: Material(
            color: Colors.white,
            elevation: 3,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Tap the map to set $label'),
                  TextButton(
                    onPressed: () => setState(() => _pickingOnMap = false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
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
      case ServiceType.batteryBoost:
      case ServiceType.flatTireChange:
      case ServiceType.fuelDelivery:
        return _buildComingSoon();
    }
  }

  // ---------------- Towing ----------------
  Widget _buildTowingDetails() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _onAddCar,
            icon: const Icon(Icons.add, size: 18, color: Colors.black54),
            label: const Text(
              'Add Car',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          ),
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
                    child: const Icon(Icons.location_on_outlined, size: 24),
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
        const SizedBox(height: 14),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _onSetLocationOnMap,
              icon: const Icon(
                Icons.map_outlined,
                size: 20,
                color: Colors.black87,
              ),
              label: const Text(
                'Set Location on map',
                style: TextStyle(color: Colors.black87, fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                side: BorderSide(color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildRouteSummary()),
          ],
        ),
      ],
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

  Widget _locationField(
    TextEditingController controller,
    String hint,
    _PickTarget target,
  ) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 14),
      textInputAction: TextInputAction.search,
      onTap: () => setState(() => _activeField = target),
      onSubmitted: (text) => _onFieldSubmitted(target, text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  Widget _buildComingSoon() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Image.asset(
            _config.iconPath,
            width: 32,
            height: 32,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.build_outlined, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            'Details for this service are coming soon',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
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

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _snack('Please turn on location services');
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
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
    _mapController.move(here, 16);
  }

  /// Runs once the map is ready: gets a first fix, then streams live updates.
  Future<void> _startLocationTracking() async {
    try {
      if (!await _ensureLocationPermission()) {
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
    });

    if (isFirstFix) {
      _hasCenteredOnUser = true;
      _mapController.move(here, 16);
      // Prefill pickup once with the first fix (tow truck only).
      if (widget.serviceType == ServiceType.towTruck) {
        _setPoint(_PickTarget.pickup, here).then((_) {
          if (mounted) setState(() => _activeField = _PickTarget.dropoff);
        });
      }
    }
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

    setState(() {
      if (target == _PickTarget.pickup) {
        _pickup = point;
      } else {
        _dropoff = point;
      }
    });

    if (label != null) {
      controller.text = label;
    } else {
      controller.text =
          '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
      final address = await _MapApi.reverseGeocode(point);
      if (!mounted) return;
      if (address != null) controller.text = address;
    }

    await _updateRoute();
  }

  Future<void> _updateRoute() async {
    final a = _pickup;
    final b = _dropoff;
    if (a == null || b == null) return;

    setState(() => _loadingRoute = true);
    final result = await _MapApi.route(a, b);
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

    // The map now sits above the sheet, so only small paddings are needed.
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: result.points,
        padding: const EdgeInsets.fromLTRB(50, 100, 50, 80),
      ),
    );
  }

  // ---------------- Actions ----------------
  Future<void> _onFieldSubmitted(_PickTarget target, String text) async {
    final query = text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();

    final point = await _MapApi.geocode(query);
    if (!mounted) return;
    if (point == null) {
      _snack('Location not found. Try a more specific address.');
      return;
    }

    await _setPoint(target, point, label: query);
    if (_routePoints.isEmpty && mounted) {
      _mapController.move(point, 15);
    }
  }

  /// Called when a pin (map or sheet icon) is tapped: switch to that target
  /// and let the user tap the map to choose a new spot for it.
  void _startRepick(_PickTarget target) {
    FocusScope.of(context).unfocus();
    setState(() {
      _activeField = target;
      _pickingOnMap = true;
    });
  }

  void _onSetLocationOnMap() {
    FocusScope.of(context).unfocus();
    setState(() => _pickingOnMap = true);
  }

  Future<void> _onMapTap(LatLng point) async {
    if (!_pickingOnMap) return;
    final target = _activeField;
    setState(() => _pickingOnMap = false);

    await _setPoint(target, point);

    // After setting pickup, move on to drop-off automatically.
    if (mounted && target == _PickTarget.pickup && _dropoff == null) {
      setState(() => _activeField = _PickTarget.dropoff);
    }
  }

  void _onAddCar() {}

  void _onConfirm() {
    if (widget.serviceType == ServiceType.towTruck &&
        (_pickup == null || _dropoff == null)) {
      _snack('Please set both pickup and drop-off locations');
      return;
    }
    // TODO: create the service request (pickup, dropoff, distance, duration).
  }
}
