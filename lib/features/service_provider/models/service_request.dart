import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceRequest {
  final String id;
  final String providerUid;
  final String driverName;
  final String serviceName;
  final String location;
  final String vehicleLabel;
  final int price;
  final String status;

  const ServiceRequest({
    required this.id,
    required this.providerUid,
    required this.driverName,
    required this.serviceName,
    required this.location,
    required this.vehicleLabel,
    required this.price,
    required this.status,
  });

  factory ServiceRequest.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final map = snapshot.data() ?? const <String, dynamic>{};
    return ServiceRequest(
      id: snapshot.id,
      providerUid: map['providerUid'] as String? ?? '',
      driverName: map['driverName'] as String? ?? 'Customer',
      serviceName: map['serviceName'] as String? ?? 'Roadside service',
      location: map['location'] as String? ?? 'Location unavailable',
      vehicleLabel: map['vehicleLabel'] as String? ?? 'Vehicle unavailable',
      price: (map['price'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'pending',
    );
  }
}
