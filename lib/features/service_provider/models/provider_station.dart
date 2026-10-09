import 'package:cloud_firestore/cloud_firestore.dart';

class ProviderStation {
  final String id;
  final String providerUid;
  final String name;
  final String stationType;
  final String address;
  final String phone;
  final String operatingHours;
  final List<String> services;
  final bool isActive;
  final double rating;
  final int reviewCount;

  const ProviderStation({
    required this.id,
    required this.providerUid,
    required this.name,
    required this.stationType,
    required this.address,
    required this.phone,
    required this.operatingHours,
    this.services = const [],
    this.isActive = true,
    this.rating = 5.0,
    this.reviewCount = 0,
  });

  Map<String, dynamic> toMap() => {
    'providerUid': providerUid,
    'name': name,
    'stationType': stationType,
    'address': address,
    'phone': phone,
    'operatingHours': operatingHours,
    'services': services,
    'isActive': isActive,
    'rating': rating,
    'reviewCount': reviewCount,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory ProviderStation.fromMap(String id, Map<String, dynamic> map) {
    return ProviderStation(
      id: id,
      providerUid: map['providerUid'] as String? ?? '',
      name: map['name'] as String? ?? '',
      stationType: map['stationType'] as String? ?? 'Auto Repair & Garage',
      address: map['address'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      operatingHours: map['operatingHours'] as String? ?? '08:00 AM - 08:00 PM',
      services: (map['services'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isActive: map['isActive'] as bool? ?? true,
      rating: ((map['rating'] ?? 5.0) as num).toDouble(),
      reviewCount: ((map['reviewCount'] ?? 0) as num).toInt(),
    );
  }

  ProviderStation copyWith({
    String? id,
    String? providerUid,
    String? name,
    String? stationType,
    String? address,
    String? phone,
    String? operatingHours,
    List<String>? services,
    bool? isActive,
    double? rating,
    int? reviewCount,
  }) {
    return ProviderStation(
      id: id ?? this.id,
      providerUid: providerUid ?? this.providerUid,
      name: name ?? this.name,
      stationType: stationType ?? this.stationType,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      operatingHours: operatingHours ?? this.operatingHours,
      services: services ?? this.services,
      isActive: isActive ?? this.isActive,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
    );
  }
}
