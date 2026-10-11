class ServiceCenter {
  final String id;
  final String name;
  final String phone;
  final String address;
  final double latitude;
  final double longitude;
  final double fullServicePrice; // LKR
  final double rating;
  final int reviewCount;
  final double distanceKm; // calculated from the user's location
  final int openHour; // 0-24
  final int closeHour; // 0-24
  final String ownerId; // provider uid
  final bool manuallyClosed; // provider switched "accepting customers" off
  final List<String> services; // services offered by the center

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
    this.ownerId = '',
    this.manuallyClosed = false,
    this.services = const [],
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
      ownerId: ownerId,
      manuallyClosed: manuallyClosed,
      services: services,
    );
  }

  /// false until at least one driver has reviewed this center.
  bool get hasRating => reviewCount > 0;

  /// Open right now = provider has not closed it AND inside working hours.
  bool get isOpenNow {
    if (manuallyClosed) return false;
    final now = DateTime.now();
    final h = now.hour + now.minute / 60;
    if (openHour == 0 && closeHour == 24) return true;
    if (openHour <= closeHour) return h >= openHour && h < closeHour;
    return h >= openHour || h < closeHour; // overnight hours
  }

  String get hoursLabel {
    if (openHour == 0 && closeHour == 24) return 'Open 24 hours';
    return '${hourLabel(openHour)} - ${hourLabel(closeHour)}';
  }

  static String hourLabel(int h) {
    final hh = h % 24;
    final suffix = hh >= 12 ? 'PM' : 'AM';
    final h12 = hh % 12 == 0 ? 12 : hh % 12;
    return '$h12:00 $suffix';
  }

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
      ownerId: (data['ownerId'] ?? '') as String,
      manuallyClosed: (data['manuallyClosed'] ?? false) as bool,
      services: ((data['services'] ?? const []) as List)
          .map((e) => e.toString())
          .toList(),
    );
  }
}