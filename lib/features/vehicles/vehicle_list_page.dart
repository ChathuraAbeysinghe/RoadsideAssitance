import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../entities/vehicle.dart';
import '../_share/navbar/app_bottom_nav_bar_assisstance_provider.dart';
import 'add_vehicle_page.dart';

enum _VehicleAction { edit, setActive, remove }

class _VehicleListData {
  final List<Vehicle> vehicles;
  final String? activeVehicleId;

  const _VehicleListData({
    required this.vehicles,
    required this.activeVehicleId,
  });
}

/// Shows the signed-in user's owned vehicles.
///
/// - Empty state: illustration + message + full-width "Add New Vehicle"
///   button (see reference image 1).
/// - Populated state: one rounded tile per vehicle with a small
///   per-type illustration, name/plate text (active vehicle marked with
///   a small yellow star next to the name), an overflow menu
///   (Edit / Set as active / Remove), and an "Add Vehicle" row pinned
///   at the bottom of the list (reference image 2).
class VehicleListPage extends StatefulWidget {
  final String uid;

  const VehicleListPage({super.key, required this.uid});

  @override
  State<VehicleListPage> createState() => _VehicleListPageState();
}

class _VehicleListPageState extends State<VehicleListPage> {
  late Future<_VehicleListData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  /// Loads the user's vehicles and their current activeVehicleId together,
  /// so the tile list can show which one is active without a second
  /// round-trip.
  Future<_VehicleListData> _loadData() async {
    final results = await Future.wait([
      fetchVehiclesForUser(widget.uid),
      FirebaseFirestore.instance.collection('users').doc(widget.uid).get(),
    ]);

    final vehicles = results[0] as List<Vehicle>;
    final userDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;
    final activeVehicleId = userDoc.data()?['activeVehicleId'] as String?;

    return _VehicleListData(
      vehicles: vehicles,
      activeVehicleId: activeVehicleId,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _dataFuture = _loadData();
    });
    await _dataFuture;
  }

  Future<void> _onAddVehicle() async {
    final result = await Navigator.of(context).push<Vehicle>(
      MaterialPageRoute(builder: (_) => AddVehiclePage(ownerUid: widget.uid)),
    );
    if (result != null) {
      await _refresh();
    }
  }

  // ----------------------------------------------------------------
  // Overflow menu
  // ----------------------------------------------------------------

  Future<void> _onVehicleMenuTap(Vehicle vehicle, bool isActive) async {
    final action = await showModalBottomSheet<_VehicleAction>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, _VehicleAction.edit),
            ),
            ListTile(
              leading: Icon(
                isActive ? Icons.star_rounded : Icons.star_border_rounded,
                color: Colors.amber,
              ),
              title: Text(isActive ? 'Active vehicle' : 'Set as active'),
              enabled: !isActive,
              onTap: isActive
                  ? null
                  : () => Navigator.pop(context, _VehicleAction.setActive),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, _VehicleAction.remove),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _VehicleAction.edit:
        await _onEditVehicle(vehicle);
        break;
      case _VehicleAction.setActive:
        await _onSetActiveVehicle(vehicle);
        break;
      case _VehicleAction.remove:
        await _onRemoveVehicle(vehicle);
        break;
    }
  }

  Future<void> _onEditVehicle(Vehicle vehicle) async {
    // TODO: this assumes AddVehiclePage has a `vehicleToEdit` param that
    // pre-fills the form and saves back to the same doc ID instead of
    // creating a new vehicle. Adjust if AddVehiclePage's actual
    // signature differs.
    final result = await Navigator.of(context).push<Vehicle>(
      MaterialPageRoute(
        builder: (_) =>
            AddVehiclePage(ownerUid: widget.uid, vehicleToEdit: vehicle),
      ),
    );
    if (result != null) {
      await _refresh();
    }
  }

  Future<void> _onSetActiveVehicle(Vehicle vehicle) async {
    try {
      // Active vehicle is tracked on the user doc (AppUser.activeVehicleId),
      // not on the vehicle itself — so "set as active" just writes this
      // vehicle's id there.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({'activeVehicleId': vehicle.id});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${vehicle.displayLabel} set as active vehicle'),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not set active vehicle. Try again.'),
        ),
      );
    }
  }

  Future<void> _onRemoveVehicle(Vehicle vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove vehicle?'),
        content: Text(
          'This will remove ${vehicle.displayLabel} from your vehicles.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('vehicles')
          .doc(vehicle.id)
          .delete();

      // If the deleted vehicle was the active one, clear the reference on
      // the user doc so activeVehicleId doesn't point at a dead vehicle.
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid);
      final userDoc = await userRef.get();
      if (userDoc.data()?['activeVehicleId'] == vehicle.id) {
        await userRef.update({'activeVehicleId': null});
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${vehicle.displayLabel} removed')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove vehicle. Try again.')),
      );
    }
  }

  // ----------------------------------------------------------------
  // Build
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: FutureBuilder<_VehicleListData>(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return _buildErrorState();
                  }

                  final data = snapshot.data;
                  final vehicles = data?.vehicles ?? [];
                  if (vehicles.isEmpty) {
                    return _buildEmptyState();
                  }

                  return _buildVehicleList(vehicles, data?.activeVehicleId);
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNavBarAssisstanceProvider(
        activeIndex: 2,
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
          const SizedBox(height: 0),
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

  Widget _buildVehicleList(List<Vehicle> vehicles, String? activeVehicleId) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          ...vehicles.map(
            (v) => _buildVehicleTile(v, isActive: v.id == activeVehicleId),
          ),
          _buildAddVehicleTile(),
        ],
      ),
    );
  }

  Widget _buildVehicleTile(Vehicle vehicle, {required bool isActive}) {
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${vehicle.make} ${vehicle.model}'.trim(),
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: Colors.amber,
                      ),
                    ],
                  ],
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
            onPressed: () => _onVehicleMenuTap(vehicle, isActive),
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

  // Per-type illustration assets. All types point at the same
  // placeholder icon for now — swap each case to its own asset once the
  // real artwork exists (the switch is kept so that's a one-line change
  // per type later, instead of hunting down a single constant).
  String _iconAssetFor(VehicleType type) => switch (type) {
    VehicleType.car => 'assets/images/vehicle-car.png',
    VehicleType.van => 'assets/images/vehicle-van.png',
    VehicleType.motorbike => 'assets/images/vehicle-bike.png',
    VehicleType.threeWheeler => 'assets/images/vehicle-threewheel.png',
    VehicleType.truck => 'assets/images/vehicle-truck.png',
    VehicleType.bus => 'assets/images/vehicle-bus.png',
    VehicleType.towtruck => 'assets/images/vehicle-towtruck.png',
  };

  IconData _fallbackIconFor(VehicleType type) => switch (type) {
    VehicleType.car => Icons.directions_car_rounded,
    VehicleType.van => Icons.airport_shuttle_rounded,
    VehicleType.motorbike => Icons.two_wheeler_rounded,
    VehicleType.threeWheeler => Icons.electric_rickshaw_rounded,
    VehicleType.truck => Icons.local_shipping_rounded,
    VehicleType.bus => Icons.directions_bus_rounded,
    VehicleType.towtruck => Icons.local_shipping_rounded,
  };
}
