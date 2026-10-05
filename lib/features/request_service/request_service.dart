import 'dart:async';
import 'dart:convert';

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

const String _placeholderIcon = 'assets/images/icon-towtruck.png';
const String _pickupPinPath = 'assets/images/pickup-point2.png';
const String _assistanceIcon = 'assets/images/assistance1.png';

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

enum _FuelType { petrol, diesel }

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
  bool _trackingActive = false;

  // Live nearby assistance providers shown on the map.
  StreamSubscription<List<NearbyProvider>>? _providersSub;
  List<NearbyProvider> _providers = const [];

  // Provider whose info card is open, and a cache of loaded details
  // (name, rating, phone, photo).
  String? _selectedUid;
  final Map<String, Future<AppUser?>> _providerDetails = {};

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadActiveVehicle();
    _watchProviders();
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
    _providersSub?.cancel();
    _litersController.dispose();
    _litersFocus.dispose();
    _positionSub?.cancel();
    _mapController.dispose();
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  // ---------------- Nearby providers ----------------
  void _watchProviders() {
    _providersSub = watchNearbyProviders(widget.serviceType).listen((list) {
      if (mounted) setState(() => _providers = list);
    }, onError: (_) {});
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

  Widget _buildProviderMarkers(double radiusM) {
    const distance = Distance();
    final center = _pickup ?? _userLocation ?? _initialCenter;

    final nearby = _providers.where((p) {
      final point = LatLng(p.location.latitude, p.location.longitude);
      return distance.as(LengthUnit.Meter, center, point) <= radiusM;
    }).toList();

    NearbyProvider? selected;
    for (final p in nearby) {
      if (p.uid == _selectedUid) selected = p;
    }

    return MarkerLayer(
      markers: [
        for (final p in nearby)
          Marker(
            key: ValueKey(p.uid),
            point: LatLng(p.location.latitude, p.location.longitude),
            width: 30,
            height: 30,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _selectedUid = p.uid),
              child: Image.asset(
                _assistanceIcon,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.local_shipping,
                  color: _brandRed,
                  size: 20,
                ),
              ),
            ),
          ),
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
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
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
                    child: CircularProgressIndicator(strokeWidth: 2),
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
      color: Colors.grey.shade300,
      child: Icon(Icons.person, color: Colors.grey.shade600),
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
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.star, size: 15, color: Colors.amber),
                  const SizedBox(width: 3),
                  Text(
                    rating.count > 0
                        ? '${rating.average.toStringAsFixed(1)} (${rating.count})'
                        : 'No ratings yet',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
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
        onTap: (_, point) {
          // Tapping the map also closes any open provider info card.
          if (_selectedUid != null) setState(() => _selectedUid = null);
          _onMapTap(point);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _appPackageName,
        ),
        // GPS accuracy circle
        if (_pickingOnMap && _userLocation != null && _userAccuracy > 0)
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
            // Live user location (blue dot), only shown while picking on the
            // map. Drawn first so pins sit on top.
            if (_pickingOnMap && _userLocation != null)
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
                    color: Color.fromARGB(255, 210, 0, 0),
                    size: 40,
                  ),
                ),
              ),
          ],
        ),
        // Live nearby assistance. Last child so the info card draws on top.
        // Hidden while picking so it can't swallow taps meant for choosing
        // a location.
        if (!_pickingOnMap) _buildProviderMarkers(kSearchRadiiKm.last * 1000),
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
    final label = _isSingleLocation
        ? 'location'
        : (_activeField == _PickTarget.pickup ? 'pickup' : 'drop-off');
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
        Align(alignment: Alignment.centerLeft, child: _buildVehicleButton()),
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
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _onSetLocationOnMap,
          icon: const Icon(Icons.map_outlined, size: 20, color: Colors.black87),
          label: const Text(
            'Set Location on map',
            style: TextStyle(color: Colors.black87, fontSize: 12),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            side: BorderSide(color: Colors.grey.shade400),
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
    _mapController.move(here, 16);
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
    });

    if (isFirstFix) {
      _hasCenteredOnUser = true;
      _mapController.move(here, 16);
      // Prefill pickup once with the first fix (tow truck only).
      if (_isTow || _isSingleLocation) {
        _setPoint(_PickTarget.pickup, here).then((_) {
          // Only towing has a drop-off to move on to.
          if (mounted && _isTow) {
            setState(() => _activeField = _PickTarget.dropoff);
          }
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
    if (mounted && _isTow && target == _PickTarget.pickup && _dropoff == null) {
      setState(() => _activeField = _PickTarget.dropoff);
    }
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
          ),
        ),
      );
      return;
    }
  }
}
