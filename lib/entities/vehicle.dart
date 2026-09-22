import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';

// ============================================================
// VehicleType
// ============================================================

enum VehicleType { car, van, motorbike, threeWheeler, truck, bus, towtruck }

extension VehicleTypeX on VehicleType {
  String get name => switch (this) {
    VehicleType.car => 'car',
    VehicleType.van => 'van',
    VehicleType.motorbike => 'motorbike',
    VehicleType.threeWheeler => 'threeWheeler',
    VehicleType.truck => 'truck',
    VehicleType.bus => 'bus',
    VehicleType.towtruck => 'towtruck',
  };

  static VehicleType fromString(String value) => switch (value) {
    'car' => VehicleType.car,
    'van' => VehicleType.van,
    'motorbike' => VehicleType.motorbike,
    'threeWheeler' => VehicleType.threeWheeler,
    'truck' => VehicleType.truck,
    'bus' => VehicleType.bus,
    'towtruck' => VehicleType.towtruck,
    _ => throw ArgumentError('Unknown vehicle type: $value'),
  };
}

// ============================================================
// Vehicle
// ============================================================

class Vehicle {
  final String id;
  final String ownerUid;
  final VehicleType vehicleType;
  final String make;
  final String model;
  final String plateNumber;
  final String color;
  final String photoPath;

  const Vehicle({
    required this.id,
    required this.ownerUid,
    required this.vehicleType,
    required this.make,
    required this.model,
    required this.plateNumber,
    this.color = '',
    this.photoPath = '',
  });

  factory Vehicle.fromMap(String id, Map<String, dynamic> map) {
    return Vehicle(
      id: id,
      ownerUid: map['ownerUid'] as String? ?? '',
      vehicleType: VehicleTypeX.fromString(
        map['vehicleType'] as String? ?? 'car',
      ),
      make: map['make'] as String? ?? '',
      model: map['model'] as String? ?? '',
      plateNumber: map['plateNumber'] as String? ?? '',
      color: map['color'] as String? ?? '',
      photoPath: map['photoPath'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'ownerUid': ownerUid,
    'vehicleType': vehicleType.name,
    'make': make,
    'model': model,
    'plateNumber': plateNumber,
    'color': color,
    'photoPath': photoPath,
  };

  Vehicle copyWith({
    VehicleType? vehicleType,
    String? make,
    String? model,
    String? plateNumber,
    String? color,
    String? photoPath,
  }) {
    return Vehicle(
      id: id,
      ownerUid: ownerUid,
      vehicleType: vehicleType ?? this.vehicleType,
      make: make ?? this.make,
      model: model ?? this.model,
      plateNumber: plateNumber ?? this.plateNumber,
      color: color ?? this.color,
      photoPath: photoPath ?? this.photoPath,
    );
  }

  /// Convenience display label, e.g. "Toyota Aqua · ABC-1234".
  String get displayLabel => '$make $model · $plateNumber'.trim();
}

// ============================================================
// Fetch helpers
// ============================================================

/// Fetches a single vehicle document by its ID from the top-level
/// `vehicles` Firestore collection. Returns null if it doesn't exist.
Future<Vehicle?> fetchVehicleById(String vehicleId) async {
  final doc = await FirebaseFirestore.instance
      .collection('vehicles')
      .doc(vehicleId)
      .get();

  if (!doc.exists) return null;
  return Vehicle.fromMap(doc.id, doc.data()!);
}

/// Looks up [user]'s currently active vehicle, using
/// [AppUser.activeVehicleId] as the document ID.
///
/// Returns null if the user has no active vehicle set, or if the
/// referenced vehicle document no longer exists (e.g. it was deleted
/// after being set active).
Future<Vehicle?> fetchActiveVehicle(AppUser user) async {
  final vehicleId = user.activeVehicleId;
  if (vehicleId == null || vehicleId.isEmpty) return null;
  return fetchVehicleById(vehicleId);
}

/// Fetches all vehicles owned by [uid], most-recently-added order is not
/// guaranteed unless you add a createdAt field and orderBy clause later.
Future<List<Vehicle>> fetchVehiclesForUser(String uid) async {
  final query = await FirebaseFirestore.instance
      .collection('vehicles')
      .where('ownerUid', isEqualTo: uid)
      .get();

  return query.docs.map((doc) => Vehicle.fromMap(doc.id, doc.data())).toList();
}
