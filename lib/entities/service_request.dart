import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';

// ============================================================
// Search settings
// ============================================================

/// The customer app widens the search through these radii (km), one per
/// stage, while the request is pending. Providers only see a request when
/// they're within its current [ServiceRequest.searchRadiusKm].
const List<double> kSearchRadiiKm = [5, 10, 15];

/// How long a request stays pending before it expires.
const Duration kSearchTimeout = Duration(minutes: 2);

// ============================================================
// RequestStatus
// ============================================================

enum RequestStatus {
  pending,
  accepted,
  onTheWay,
  arrived,
  inProgress,
  completed,
  cancelled,
  expired,
}

RequestStatus _statusFromString(String? value) => RequestStatus.values
    .firstWhere((s) => s.name == value, orElse: () => RequestStatus.pending);

/// Human readable service name for lists/cards.
String serviceTypeTitle(ServiceType t) => switch (t) {
  ServiceType.towTruck => 'Emergency Towing',
  ServiceType.mechanic => 'Mechanic',
  ServiceType.fuelDelivery => 'Fuel Delivery',
  ServiceType.flatTireChange => 'Flat Tire',
  ServiceType.batteryBoost => 'Battery Boosting',
};

// ============================================================
// ServiceRequest
// ============================================================

class ServiceRequest {
  final String id;
  final String customerUid;
  final ServiceType serviceType;
  final RequestStatus status;
  final String? providerUid;

  final GeoLocation pickup;
  final String pickupAddress;

  /// Towing only.
  final GeoLocation? dropoff;
  final String? dropoffAddress;

  /// Snapshot of the vehicle at request time (id, make, model, plate...).
  final Map<String, dynamic>? vehicle;
  final String notes;

  /// Fuel delivery only.
  final int? liters;
  final String? fuelType;

  final double? distanceKm;
  final int? durationMin;

  final double serviceFee;
  final double fuelCost;
  final double totalAmount;
  final String paymentMethod;

  final double searchRadiusKm;
  final DateTime? createdAt;
  final DateTime expiresAt;

  const ServiceRequest({
    this.id = '',
    required this.customerUid,
    required this.serviceType,
    this.status = RequestStatus.pending,
    this.providerUid,
    required this.pickup,
    required this.pickupAddress,
    this.dropoff,
    this.dropoffAddress,
    this.vehicle,
    this.notes = '',
    this.liters,
    this.fuelType,
    this.distanceKm,
    this.durationMin,
    required this.serviceFee,
    this.fuelCost = 0,
    required this.totalAmount,
    this.paymentMethod = 'cash',
    this.searchRadiusKm = 5,
    this.createdAt,
    required this.expiresAt,
  });

  factory ServiceRequest.fromMap(String id, Map<String, dynamic> map) {
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;

    return ServiceRequest(
      id: id,
      customerUid: map['customerUid'] as String? ?? '',
      serviceType: ServiceTypeX.fromString(map['serviceType'] as String),
      status: _statusFromString(map['status'] as String?),
      providerUid: map['providerUid'] as String?,
      pickup: GeoLocation.fromMap(map['pickup'] as Map<String, dynamic>?),
      pickupAddress: map['pickupAddress'] as String? ?? '',
      dropoff: map['dropoff'] == null
          ? null
          : GeoLocation.fromMap(map['dropoff'] as Map<String, dynamic>?),
      dropoffAddress: map['dropoffAddress'] as String?,
      vehicle: (map['vehicle'] as Map?)?.cast<String, dynamic>(),
      notes: map['notes'] as String? ?? '',
      liters: (map['liters'] as num?)?.toInt(),
      fuelType: map['fuelType'] as String?,
      distanceKm: (map['distanceKm'] as num?)?.toDouble(),
      durationMin: (map['durationMin'] as num?)?.toInt(),
      serviceFee: (map['serviceFee'] as num?)?.toDouble() ?? 0,
      fuelCost: (map['fuelCost'] as num?)?.toDouble() ?? 0,
      totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0,
      paymentMethod: map['paymentMethod'] as String? ?? 'cash',
      searchRadiusKm: (map['searchRadiusKm'] as num?)?.toDouble() ?? 5,
      createdAt: ts(map['createdAt']),
      expiresAt: ts(map['expiresAt']) ?? DateTime.now(),
    );
  }

  /// Used when creating the document. `createdAt` is set by the server.
  Map<String, dynamic> toMap() => {
    'customerUid': customerUid,
    'serviceType': serviceType.name,
    'status': status.name,
    'providerUid': providerUid,
    'pickup': pickup.toMap(),
    'pickupAddress': pickupAddress,
    'dropoff': dropoff?.toMap(),
    'dropoffAddress': dropoffAddress,
    'vehicle': vehicle,
    'notes': notes,
    'liters': liters,
    'fuelType': fuelType,
    'distanceKm': distanceKm,
    'durationMin': durationMin,
    'serviceFee': serviceFee,
    'fuelCost': fuelCost,
    'totalAmount': totalAmount,
    'paymentMethod': paymentMethod,
    'searchRadiusKm': searchRadiusKm,
    'createdAt': FieldValue.serverTimestamp(),
    'expiresAt': Timestamp.fromDate(expiresAt),
  };

  /// e.g. "Toyota Aqua · ABC-1234", or null if no vehicle was attached.
  String? get vehicleLabel {
    final v = vehicle;
    if (v == null) return null;
    return '${v['make'] ?? ''} ${v['model'] ?? ''} · ${v['plateNumber'] ?? ''}'
        .trim();
  }
}

// ============================================================
// Firestore helpers
// ============================================================

CollectionReference<Map<String, dynamic>> get _requests =>
    FirebaseFirestore.instance.collection('service_requests');

/// Creates the request document and returns its generated ID.
Future<String> createServiceRequest(ServiceRequest request) async {
  final ref = _requests.doc();
  await ref.set(request.toMap());
  return ref.id;
}

/// Live updates for a single request (null if it doesn't exist).
Stream<ServiceRequest?> watchRequest(String id) {
  return _requests.doc(id).snapshots().map((snap) {
    final data = snap.data();
    if (data == null) return null;
    return ServiceRequest.fromMap(snap.id, data);
  });
}

/// Widens the search radius (customer app, while still pending).
Future<void> updateSearchRadius(String id, double km) {
  return _requests.doc(id).update({'searchRadiusKm': km});
}

/// Cancels a request that is still pending or accepted.
Future<void> cancelRequest(String id) {
  final ref = _requests.doc(id);
  return FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await tx.get(ref);
    final status = snap.data()?['status'];
    if (status == 'pending' || status == 'accepted') {
      tx.update(ref, {'status': 'cancelled'});
    }
  });
}

/// Marks a still-pending request as expired (nobody accepted in time).
Future<void> expireRequest(String id) {
  final ref = _requests.doc(id);
  return FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await tx.get(ref);
    if (snap.data()?['status'] == 'pending') {
      tx.update(ref, {'status': 'expired'});
    }
  });
}

/// "Try again": puts an expired request back to pending with a fresh
/// timeout and the smallest search radius. Returns false if it wasn't
/// expired any more (e.g. someone accepted it just in time).
Future<bool> renewRequest(String id) {
  final ref = _requests.doc(id);
  return FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await tx.get(ref);
    if (snap.data()?['status'] != 'expired') return false;
    tx.update(ref, {
      'status': 'pending',
      'searchRadiusKm': kSearchRadiiKm.first,
      'expiresAt': Timestamp.fromDate(DateTime.now().add(kSearchTimeout)),
    });
    return true;
  });
}

enum AcceptResult { success, alreadyTaken, expired, notFound }

/// Provider accepts a request. This is a transaction so that if several
/// providers tap Accept at the same time, only the first one wins.
Future<AcceptResult> acceptRequest({
  required String requestId,
  required String providerUid,
}) {
  final ref = _requests.doc(requestId);
  return FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await tx.get(ref);
    final data = snap.data();
    if (data == null) return AcceptResult.notFound;

    if (data['status'] != 'pending' || data['providerUid'] != null) {
      return AcceptResult.alreadyTaken;
    }

    final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
    if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
      return AcceptResult.expired;
    }

    tx.update(ref, {
      'status': 'accepted',
      'providerUid': providerUid,
      'acceptedAt': FieldValue.serverTimestamp(),
    });
    return AcceptResult.success;
  });
}

/// Live list of pending requests for the given service types.
///
/// Distance / expiry filtering happens on the device (see the provider
/// screen). For large scale, replace with a geohash query.
Stream<List<ServiceRequest>> watchPendingRequests(Set<ServiceType> services) {
  if (services.isEmpty) return Stream.value(const []);
  return _requests
      .where('status', isEqualTo: 'pending')
      .where('serviceType', whereIn: services.map((s) => s.name).toList())
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => ServiceRequest.fromMap(d.id, d.data()))
            .toList(),
      );
}

// ============================================================
// Nearby providers (for the live map on the searching screen)
// ============================================================

class NearbyProvider {
  final String uid;
  final GeoLocation location;
  const NearbyProvider({required this.uid, required this.location});
}

/// Live list of available providers that offer [service], with their
/// current location. Distance filtering happens on the device.
///
/// NOTE: this query may ask for a composite index on `users`
/// (userType, isAvailable, services). Firestore prints a link to create it
/// in the debug console the first time it runs.
Stream<List<NearbyProvider>> watchNearbyProviders(ServiceType service) {
  return FirebaseFirestore.instance
      .collection('users')
      .where('userType', isEqualTo: UserType.assistanceProvider.name)
      .where('isAvailable', isEqualTo: true)
      .where('services', arrayContains: service.name)
      .snapshots()
      .map((snap) {
        final list = <NearbyProvider>[];
        for (final d in snap.docs) {
          final loc = GeoLocation.fromMap(
            d.data()['currentLocation'] as Map<String, dynamic>?,
          );
          // Skip providers that haven't reported a location yet.
          if (loc.latitude == 0 && loc.longitude == 0) continue;
          list.add(NearbyProvider(uid: d.id, location: loc));
        }
        return list;
      });
}
