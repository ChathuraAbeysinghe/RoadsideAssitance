import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../entities/app_user.dart';
import 'request_service.dart';
import '../nearby_centers/service_centers_near_location_page.dart';

class ServiceLocationPage extends StatefulWidget {
  final ServiceType serviceType;
  final UserType userType;

  const ServiceLocationPage({
    super.key,
    required this.serviceType,
    required this.userType,
  });

  @override
  State<ServiceLocationPage> createState() => _ServiceLocationPageState();
}

class _ServiceLocationPageState extends State<ServiceLocationPage> {
  static const Color _red = Color(0xFFE30613);
  static const LatLng _fallback = LatLng(6.9271, 79.8612); // Colombo

  final MapController _map = MapController();
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;

  bool _mapReady = false;
  LatLng _initialCenter = _fallback;
  LatLng? _myPos; // user's current GPS position
  LatLng? _selected; // location chosen for the request

  bool _pickMode = false; // "Set location on map" mode
  LatLng _pickCenter = _fallback;
  String _pickAddress = '';

  bool _busy = false;
  bool _textDirty = false;

  // ---------- service texts ----------
  String get _title {
    switch (widget.serviceType) {
      case ServiceType.towTruck:
        return 'Request Vehicle Tow';
      case ServiceType.mechanic:
        return 'Request Mechanic';
      case ServiceType.batteryBoost:
        return 'Request Jump Start';
      case ServiceType.flatTireChange:
        return 'Request Flat Tire';
      case ServiceType.fuelDelivery:
        return 'Request Fuel Delivery';
      default:
        return 'Request Service';
    }
  }

  String get _subtitle {
    switch (widget.serviceType) {
      case ServiceType.towTruck:
        return 'Get your vehicle towed to safety';
      case ServiceType.mechanic:
        return 'A mechanic will come to you';
      case ServiceType.batteryBoost:
        return 'Get your battery jump-started';
      case ServiceType.flatTireChange:
        return 'Airing it up or replace it with your spare';
      case ServiceType.fuelDelivery:
        return 'Fuel delivered to where you are';
      default:
        return 'Tell us where you need help';
    }
  }

  // ---------- lifecycle ----------
  @override
  void initState() {
    super.initState();
    _loadInitialPosition();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _map.dispose();
    super.dispose();
  }

  // ---------- helpers ----------
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _moveTo(LatLng p, {double zoom = 16}) {
    if (!_mapReady) {
      _initialCenter = p;
      return;
    }
    try {
      _map.move(p, zoom);
    } catch (_) {}
  }

  Future<LatLng?> _currentPosition({bool showErrors = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (showErrors) _toast('Please turn on location services.');
        return null;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (showErrors) _toast('Location permission is required.');
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 10));
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      if (showErrors) _toast('Could not get your current location.');
      return null;
    }
  }

  Future<String> _addressOf(LatLng p) async {
    try {
      final list = await placemarkFromCoordinates(p.latitude, p.longitude);
      if (list.isNotEmpty) {
        final m = list.first;
        final parts = <String>[
          m.name ?? '',
          m.street ?? '',
          m.subLocality ?? '',
          m.locality ?? '',
        ].where((s) => s.trim().isNotEmpty).toSet().toList();
        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (_) {}
    return '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
  }

  // ---------- actions ----------
  Future<void> _loadInitialPosition() async {
    final p = await _currentPosition(showErrors: false);
    if (p == null || !mounted) return;
    setState(() => _myPos = p);
    _moveTo(p);
  }

  /// Target button: use the phone's GPS location.
  Future<void> _useMyLocation() async {
    final p = await _currentPosition();
    if (p == null || !mounted) return;
    setState(() {
      _myPos = p;
      _selected = p;
      _textDirty = false;
    });
    _moveTo(p);
    final addr = await _addressOf(p);
    if (!mounted) return;
    setState(() => _ctrl.text = addr);
  }

  /// Typed address -> coordinates -> marker on the map.
  Future<void> _searchAddress() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final res = await locationFromAddress(q);
      if (res.isEmpty) {
        _toast('Location not found. Try a more specific address.');
      } else {
        final p = LatLng(res.first.latitude, res.first.longitude);
        if (!mounted) return;
        setState(() {
          _selected = p;
          _textDirty = false;
        });
        _moveTo(p);
      }
    } catch (_) {
      _toast('Location not found. Try a more specific address.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tap on the map (normal mode) sets the location directly.
  Future<void> _onMapTap(LatLng p) async {
    if (_pickMode) return;
    setState(() {
      _selected = p;
      _textDirty = false;
    });
    final addr = await _addressOf(p);
    if (!mounted) return;
    setState(() => _ctrl.text = addr);
  }

  // ---------- "Set location on map" mode ----------
  void _startPickMode() {
    FocusScope.of(context).unfocus();
    LatLng start = _selected ?? _myPos ?? _initialCenter;
    try {
      if (_selected == null && _mapReady) start = _map.camera.center;
    } catch (_) {}
    setState(() {
      _pickMode = true;
      _pickCenter = start;
      _pickAddress = '';
    });
    _moveTo(start);
    _updatePickAddress();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!_pickMode) return;
    _pickCenter = camera.center;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _updatePickAddress);
  }

  Future<void> _updatePickAddress() async {
    final p = _pickCenter;
    final addr = await _addressOf(p);
    if (!mounted || !_pickMode) return;
    setState(() => _pickAddress = addr);
  }

  void _confirmPick() {
    setState(() {
      _selected = _pickCenter;
      _ctrl.text = _pickAddress;
      _textDirty = false;
      _pickMode = false;
    });
  }

  void _cancelPick() => setState(() => _pickMode = false);

  // ---------- confirm ----------
   Future<void> _confirm() async {
    if (_textDirty || (_selected == null && _ctrl.text.trim().isNotEmpty)) {
      await _searchAddress();
    }
    if (_selected == null) {
      _toast('Enter your location or set it on the map.');
      return;
    }
    if (!mounted) return;

    // Selected location: _selected (LatLng) and _ctrl.text (address).
    // TODO: pass these into RequestServicePage once it accepts a location.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceCentersNearLocationPage(
          location: _selected!,
          address: _ctrl.text.trim(),
        ),
      ),
    );
  }
  

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 15,
              onMapReady: () {
                _mapReady = true;
                final p = _myPos;
                if (p != null) _moveTo(p);
              },
              onTap: (_, point) => _onMapTap(point),
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.roadside_assitance',
              ),
              MarkerLayer(
                markers: [
                  if (_myPos != null)
                    Marker(
                      point: _myPos!,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  if (_selected != null && !_pickMode)
                    Marker(
                      point: _selected!,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_on,
                        size: 44,
                        color: _red,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Centre pin while picking on the map
          if (_pickMode)
            const IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 44),
                  child: Icon(Icons.location_on, size: 44, color: _red),
                ),
              ),
            ),

          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),

          // My-location button + bottom sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 12),
                    child: GestureDetector(
                      onTap: _useMyLocation,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
                Flexible(child: _buildSheet()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheet() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: _pickMode ? _pickContent() : _normalContent(),
        ),
      ),
    );
  }

  Widget _handle() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _redButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _red,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _normalContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _handle(),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            _subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Location',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl,
          textInputAction: TextInputAction.search,
          onChanged: (_) => _textDirty = true,
          onSubmitted: (_) => _searchAddress(),
          decoration: InputDecoration(
            hintText: 'Enter Your Location',
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            prefixIcon: const Icon(Icons.location_on_outlined),
            suffixIcon: _busy
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _red,
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _searchAddress,
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _red, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black87,
            side: BorderSide(color: Colors.grey.shade400),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: _startPickMode,
          icon: const Icon(Icons.map_outlined, size: 18),
          label: const Text(
            'Set Location on map',
            style: TextStyle(fontSize: 11),
          ),
        ),
        const SizedBox(height: 16),
        _redButton('Confirm', _confirm),
      ],
    );
  }

  Widget _pickContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _handle(),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Move the map to set your location',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.location_on_outlined, color: _red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _pickAddress.isEmpty ? 'Finding address...' : _pickAddress,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _redButton('Set this location', _confirmPick),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: _cancelPick,
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ),
      ],
    );
  }
}