class ServiceCenter {
  final String id;
  final String name;
  final String phone;
  final String address;
  final double latitude;
  final double longitude;
  final double fullServicePrice; // LKR, fixed price for a full service
  final double rating;
  final int reviewCount;
  final double distanceKm; // calculated from the user's location
  final int openHour; // 0-24 (24h clock)
  final int closeHour; // 0-24 (24h clock)

  const ServiceCenter({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.fullServicePrice,
    required this.rating,
    required this.reviewCount,
    this.distanceKm = 0,
    this.openHour = 0,
    this.closeHour = 24,
  });

  ServiceCenter copyWith({double? distanceKm}) {
    return ServiceCenter(
      id: id,
      name: name,
      phone: phone,
      address: address,
      latitude: latitude,
      longitude: longitude,
      fullServicePrice: fullServicePrice,
      rating: rating,
      reviewCount: reviewCount,
      distanceKm: distanceKm ?? this.distanceKm,
      openHour: openHour,
      closeHour: closeHour,
    );
  }

  /// true if the centre is open right now.
  bool get isOpenNow {
    final now = DateTime.now();
    final h = now.hour + now.minute / 60;
    if (openHour <= closeHour) return h >= openHour && h < closeHour;
    return h >= openHour || h < closeHour; // overnight hours
  }

  String get hoursLabel {
    if (openHour == 0 && closeHour == 24) return 'Open 24 hours';
    return '${_fmt(openHour)} - ${_fmt(closeHour)}';
  }

  static String _fmt(int h) {
    final hh = h % 24;
    final suffix = hh >= 12 ? 'PM' : 'AM';
    final h12 = hh % 12 == 0 ? 12 : hh % 12;
    return '$h12:00 $suffix';
  }

  /// Firestore collection: service_centers
  /// Fields: name, phone, address, latitude, longitude,
  ///         fullServicePrice, rating, reviewCount, openHour, closeHour
  factory ServiceCenter.fromMap(String id, Map<String, dynamic> data) {
    return ServiceCenter(
      id: id,
      name: (data['name'] ?? '') as String,
      phone: (data['phone'] ?? '') as String,
      address: (data['address'] ?? '') as String,
      latitude: ((data['latitude'] ?? 0) as num).toDouble(),
      longitude: ((data['longitude'] ?? 0) as num).toDouble(),
      fullServicePrice: ((data['fullServicePrice'] ?? 0) as num).toDouble(),
      rating: ((data['rating'] ?? 0) as num).toDouble(),
      reviewCount: ((data['reviewCount'] ?? 0) as num).toInt(),
      openHour: ((data['openHour'] ?? 0) as num).toInt(),
      closeHour: ((data['closeHour'] ?? 24) as num).toInt(),
    );
  }
}