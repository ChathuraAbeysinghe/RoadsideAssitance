import 'package:cloud_firestore/cloud_firestore.dart';

class ProviderStation {
  final String id;
  final String providerUid;
  final String name;
  final String stationType;
  final String address;
  final String phone;
  final double latitude;
  final double longitude;
  final double fullServicePrice; // LKR
  final int openHour; // 0-24
  final int closeHour; // 0-24
  final bool manuallyClosed; // provider switched "accepting customers" off
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
    this.latitude = 0,
    this.longitude = 0,
    this.fullServicePrice = 0,
    this.openHour = 8,
    this.closeHour = 20,
    this.manuallyClosed = false,
    this.services = const [],
    this.isActive = true,
    this.rating = 5.0,
    this.reviewCount = 0,
  });

  /// Stations saved before locations were added have no coordinates.
  bool get hasLocation => latitude != 0 || longitude != 0;

  bool get is24h => openHour == 0 && closeHour == 24;

  static String hourLabel(int h) {
    final hh = h % 24;
    final suffix = hh >= 12 ? 'PM' : 'AM';
    final h12 = hh % 12 == 0 ? 12 : hh % 12;
    return '$h12:00 $suffix';
  }

  String get operatingHours =>
      is24h ? 'Open 24 hours' : '${hourLabel(openHour)} - ${hourLabel(closeHour)}';

  Map<String, dynamic> toMap() => {
    'providerUid': providerUid,
    'name': name,
    'stationType': stationType,
    'address': address,
    'phone': phone,
    'latitude': latitude,
    'longitude': longitude,
    'fullServicePrice': fullServicePrice,
    'openHour': openHour,
    'closeHour': closeHour,
    'manuallyClosed': manuallyClosed,
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
      latitude: ((map['latitude'] ?? 0) as num).toDouble(),
      longitude: ((map['longitude'] ?? 0) as num).toDouble(),
      fullServicePrice: ((map['fullServicePrice'] ?? 0) as num).toDouble(),
      openHour: ((map['openHour'] ?? 8) as num).toInt(),
      closeHour: ((map['closeHour'] ?? 20) as num).toInt(),
      manuallyClosed: map['manuallyClosed'] as bool? ?? false,
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
    double? latitude,
    double? longitude,
    double? fullServicePrice,
    int? openHour,
    int? closeHour,
    bool? manuallyClosed,
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
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      fullServicePrice: fullServicePrice ?? this.fullServicePrice,
      openHour: openHour ?? this.openHour,
      closeHour: closeHour ?? this.closeHour,
      manuallyClosed: manuallyClosed ?? this.manuallyClosed,
      services: services ?? this.services,
      isActive: isActive ?? this.isActive,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
    );
  }
}