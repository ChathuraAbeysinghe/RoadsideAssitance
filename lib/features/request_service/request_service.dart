import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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

const String _placeholderIcon = 'assets/images/icon-jerrycan.png';

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

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(6.9061, 79.9697), // Malabe; replace with live location
    zoom: 15,
  );

  GoogleMapController? _mapController;
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();

  _ServiceConfig get _config => _serviceConfigs[widget.serviceType]!;

  @override
  void dispose() {
    _mapController?.dispose();
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: _initialCamera,
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              onMapCreated: (c) => _mapController = c,
            ),
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
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 12),
                  child: _circleButton(
                    icon: Icons.my_location,
                    size: 52,
                    onTap: _goToMyLocation,
                  ),
                ),
                _buildSheet(),
              ],
            ),
          ),
        ],
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
                  Image.asset(
                    _config.iconPath,
                    width: 24,
                    height: 24,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.local_shipping_outlined, size: 24),
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
                  const Icon(Icons.location_on_outlined, size: 24),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _locationField(_pickupController, 'Enter Pickup Location'),
                    Divider(height: 1, color: Colors.grey.shade400),
                    _locationField(
                      _dropoffController,
                      'Enter Drop-off Location',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              side: BorderSide(color: Colors.grey.shade400),
            ),
          ),
        ),
      ],
    );
  }

  Widget _locationField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 14),
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

  // ---------------- Actions (hook up later) ----------------
  void _goToMyLocation() {
    // TODO: get device location (geolocator) then
    // _mapController?.animateCamera(CameraUpdate.newLatLng(...));
  }

  void _onAddCar() {}
  void _onSetLocationOnMap() {}
  void _onConfirm() {}
}
