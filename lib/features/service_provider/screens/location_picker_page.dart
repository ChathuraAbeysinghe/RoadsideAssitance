import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../request_service/request_service.dart' show MapApi;

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final MapController _mapController = MapController();
  LatLng? _selectedLocation;
  LatLng? _userLocation;
  bool _locating = true;
  String _address = 'Tap on map to select location';
  bool _loadingAddress = false;

  @override
  void initState() {
    super.initState();
    _locateUser();
  }

  Future<void> _locateUser() async {
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      setState(() => _locating = false);
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _locating = false);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => _locating = false);
      return;
    }

    try {
      Position pos = await Geolocator.getCurrentPosition();
      setState(() {
        _userLocation = LatLng(pos.latitude, pos.longitude);
        _locating = false;
      });
      _mapController.move(_userLocation!, 15);
    } catch (_) {
      setState(() => _locating = false);
    }
  }

  Future<void> _onTap(LatLng point) async {
    setState(() {
      _selectedLocation = point;
      _loadingAddress = true;
      _address = 'Loading address...';
    });
    
    final addr = await MapApi.reverseGeocode(point);
    if (mounted) {
      setState(() {
        _address = addr ?? 'Unknown location';
        _loadingAddress = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location'),
        actions: [
          if (_selectedLocation != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context, {'latLng': _selectedLocation, 'address': _address});
              },
              child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(6.9271, 79.8612), // Colombo
              initialZoom: 13,
              onTap: (_, point) => _onTap(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.roadside_assitance',
              ),
              if (_userLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userLocation!,
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
                  ],
                ),
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation!,
                      width: 40,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                    )
                  ]
                )
            ],
          ),
          if (_locating)
            const Center(child: CircularProgressIndicator()),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _address,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              )
            )
          ),
          Positioned(
            right: 20,
            bottom: 100,
            child: FloatingActionButton(
              onPressed: _locateUser,
              mini: true,
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location, color: Colors.black),
            ),
          )
        ],
      ),
    );
  }
}
