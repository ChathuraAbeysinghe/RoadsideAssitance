import 'package:flutter/material.dart';

import '../../entities/vehicle.dart';
import 'add_vehicle_page.dart';

/// Shows the signed-in user's owned vehicles.
///
/// - Empty state: illustration + message + full-width "Add New Vehicle"
///   button (see reference image 1).
/// - Populated state: one rounded tile per vehicle with a small
///   per-type illustration, name/plate text, an overflow menu, and an
///   "Add Vehicle" row pinned at the bottom of the list (reference
///   image 2).
class VehicleListPage extends StatefulWidget {
  final String uid;

  const VehicleListPage({super.key, required this.uid});

  @override
  State<VehicleListPage> createState() => _VehicleListPageState();
}

class _VehicleListPageState extends State<VehicleListPage> {
  late Future<List<Vehicle>> _vehiclesFuture;

  @override
  void initState() {
    super.initState();
    _vehiclesFuture = fetchVehiclesForUser(widget.uid);
  }

  Future<void> _refresh() async {
    setState(() {
      _vehiclesFuture = fetchVehiclesForUser(widget.uid);
    });
    await _vehiclesFuture;
  }

  Future<void> _onAddVehicle() async {
    final result = await Navigator.of(context).push<Vehicle>(
      MaterialPageRoute(builder: (_) => AddVehiclePage(ownerUid: widget.uid)),
    );
    if (result != null) {
      await _refresh();
    }
  }

  void _onVehicleMenuTap(Vehicle vehicle) {
    // TODO: show a menu with actions like "Set as active", "Edit",
    // "Delete" for this vehicle.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: FutureBuilder<List<Vehicle>>(
                future: _vehiclesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return _buildErrorState();
                  }

                  final vehicles = snapshot.data ?? [];
                  if (vehicles.isEmpty) {
                    return _buildEmptyState();
                  }

                  return _buildVehicleList(vehicles);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Text(
            'Vehicles',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.chevron_left),
              style: IconButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade300),
                shape: const CircleBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/car.jpg',
            height: 160,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.directions_car_outlined,
              size: 120,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Your vehicle will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'You dont have any vehicle yet. Tap to add new vehicle below',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _onAddVehicle,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE30613),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'Add New Vehicle',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Couldn\'t load your vehicles. Pull down to try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleList(List<Vehicle> vehicles) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [...vehicles.map(_buildVehicleTile), _buildAddVehicleTile()],
      ),
    );
  }

  Widget _buildVehicleTile(Vehicle vehicle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Image.asset(
              _iconAssetFor(vehicle.vehicleType),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                _fallbackIconFor(vehicle.vehicleType),
                size: 28,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${vehicle.make} ${vehicle.model}'.trim(),
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  vehicle.plateNumber,
                  style: TextStyle(fontSize: 13.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _onVehicleMenuTap(vehicle),
            icon: const Icon(Icons.more_vert_rounded),
            color: Colors.black87,
          ),
        ],
      ),
    );
  }

  Widget _buildAddVehicleTile() {
    return InkWell(
      onTap: _onAddVehicle,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_rounded, size: 22, color: Colors.black87),
            const SizedBox(width: 14),
            const Text(
              'Add Vehicle',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // Per-type illustration assets. Replace with real artwork matching
  // the style in the reference (small isometric vehicle icons) —
  // currently falls back to a plain Material icon if the asset is
  // missing.
  String _iconAssetFor(VehicleType type) => switch (type) {
    VehicleType.car => 'assets/images/vehicle-car.png',
    VehicleType.van => 'assets/images/vehicle-van.png',
    VehicleType.motorbike => 'assets/images/vehicle-motorbike.png',
    VehicleType.threeWheeler => 'assets/images/vehicle-threewheeler.png',
    VehicleType.truck => 'assets/images/vehicle-truck.png',
    VehicleType.bus => 'assets/images/vehicle-bus.png',
  };

  IconData _fallbackIconFor(VehicleType type) => switch (type) {
    VehicleType.car => Icons.directions_car_rounded,
    VehicleType.van => Icons.airport_shuttle_rounded,
    VehicleType.motorbike => Icons.two_wheeler_rounded,
    VehicleType.threeWheeler => Icons.electric_rickshaw_rounded,
    VehicleType.truck => Icons.local_shipping_rounded,
    VehicleType.bus => Icons.directions_bus_rounded,
  };
}
