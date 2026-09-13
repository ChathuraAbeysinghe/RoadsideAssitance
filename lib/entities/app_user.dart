// ============================================================
// User type & service type enums
// ============================================================

enum UserType { driver, assistanceProvider }

extension UserTypeX on UserType {
  String get name => switch (this) {
    UserType.driver => 'driver',
    UserType.assistanceProvider => 'assistanceProvider',
  };

  static UserType fromString(String value) => switch (value) {
    'driver' => UserType.driver,
    'assistanceProvider' => UserType.assistanceProvider,
    _ => throw ArgumentError('Unknown user type: $value'),
  };
}

enum ServiceType {
  mechanic,
  towTruck,
  fuelDelivery,
  flatTireChange,
  batteryBoost,
}

extension ServiceTypeX on ServiceType {
  String get name => switch (this) {
    ServiceType.mechanic => 'mechanic',
    ServiceType.towTruck => 'towTruck',
    ServiceType.fuelDelivery => 'fuelDelivery',
    ServiceType.flatTireChange => 'flatTireChange',
    ServiceType.batteryBoost => 'batteryBoost',
  };

  static ServiceType fromString(String value) => switch (value) {
    'mechanic' => ServiceType.mechanic,
    'towTruck' => ServiceType.towTruck,
    'fuelDelivery' => ServiceType.fuelDelivery,
    'flatTireChange' => ServiceType.flatTireChange,
    'batteryBoost' => ServiceType.batteryBoost,
    _ => throw ArgumentError('Unknown service: $value'),
  };
}

// ============================================================
// GeoLocation value object
// ============================================================

/// Simple lat/lng value object. If you're using Firestore's native
/// GeoPoint, you can swap the fromMap/toMap bodies to wrap/unwrap it
/// instead of a plain map.
class GeoLocation {
  final double latitude;
  final double longitude;

  const GeoLocation({required this.latitude, required this.longitude});

  factory GeoLocation.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const GeoLocation(latitude: 0, longitude: 0);
    return GeoLocation(
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
  };
}

// ============================================================
// Rating value object (raw star totals, not a running average)
// ============================================================

/// Stores the sum of all star ratings and how many ratings were given,
/// so the average can always be recomputed from raw data with no
/// floating-point drift, and adjustments (edit/delete) stay exact.
class Rating {
  final int totalStars;
  final int count;

  const Rating({this.totalStars = 0, this.count = 0});

  factory Rating.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const Rating();
    return Rating(
      totalStars: (map['totalStars'] as num?)?.toInt() ?? 0,
      count: (map['count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {'totalStars': totalStars, 'count': count};

  /// Average star rating, e.g. 4.8. Returns 0 if no ratings yet.
  double get average => count == 0 ? 0 : totalStars / count;

  /// Returns a new Rating with the given star value (1-5) added.
  Rating addRating(int stars) {
    assert(stars >= 1 && stars <= 5, 'stars must be between 1 and 5');
    return Rating(totalStars: totalStars + stars, count: count + 1);
  }

  /// Returns a new Rating with a previously given rating removed
  /// (e.g. if a user deletes their review).
  Rating removeRating(int stars) {
    assert(stars >= 1 && stars <= 5, 'stars must be between 1 and 5');
    return Rating(
      totalStars: (totalStars - stars).clamp(0, 1 << 31).toInt(),
      count: (count - 1).clamp(0, 1 << 31).toInt(),
    );
  }

  /// Returns a new Rating with an edited rating (old value replaced by new).
  /// Count stays the same since it's the same reviewer.
  Rating editRating({required int oldStars, required int newStars}) {
    return Rating(totalStars: totalStars - oldStars + newStars, count: count);
  }
}

// ============================================================
// AppUser base class
// ============================================================

abstract class AppUser {
  final String uid;
  final String phoneNumber;
  final String name;
  final String profileImagePath;
  final UserType userType;
  final GeoLocation currentLocation;
  final Rating rating;

  AppUser({
    required this.uid,
    required this.phoneNumber,
    required this.name,
    required this.userType,
    this.profileImagePath = '',
    this.currentLocation = const GeoLocation(latitude: 0, longitude: 0),
    this.rating = const Rating(),
  });

  Map<String, dynamic> toMap();
}

// ============================================================
// Driver
// ============================================================

class Driver extends AppUser {
  Driver({
    required super.uid,
    required super.phoneNumber,
    required super.name,
    super.profileImagePath,
    super.currentLocation,
    super.rating,
  }) : super(userType: UserType.driver);

  factory Driver.fromMap(String uid, Map<String, dynamic> map) => Driver(
    uid: uid,
    phoneNumber: map['phoneNumber'] as String? ?? '',
    name: map['name'] as String? ?? '',
    profileImagePath: map['profileImagePath'] as String? ?? '',
    currentLocation: GeoLocation.fromMap(
      map['currentLocation'] as Map<String, dynamic>?,
    ),
    rating: Rating.fromMap(map['rating'] as Map<String, dynamic>?),
  );

  Driver copyWith({
    String? name,
    String? profileImagePath,
    GeoLocation? currentLocation,
    Rating? rating,
  }) {
    return Driver(
      uid: uid,
      phoneNumber: phoneNumber,
      name: name ?? this.name,
      profileImagePath: profileImagePath ?? this.profileImagePath,
      currentLocation: currentLocation ?? this.currentLocation,
      rating: rating ?? this.rating,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'phoneNumber': phoneNumber,
    'name': name,
    'userType': userType.name,
    'profileImagePath': profileImagePath,
    'currentLocation': currentLocation.toMap(),
    'rating': rating.toMap(),
  };
}

// ============================================================
// AssistanceProvider
// ============================================================

class AssistanceProvider extends AppUser {
  final Set<ServiceType> services;
  final bool isAvailable;

  AssistanceProvider({
    required super.uid,
    required super.phoneNumber,
    required super.name,
    super.profileImagePath,
    super.currentLocation,
    super.rating,
    required this.services,
    this.isAvailable = true,
  }) : super(userType: UserType.assistanceProvider);

  factory AssistanceProvider.fromMap(String uid, Map<String, dynamic> map) {
    return AssistanceProvider(
      uid: uid,
      phoneNumber: map['phoneNumber'] as String? ?? '',
      name: map['name'] as String? ?? '',
      profileImagePath: map['profileImagePath'] as String? ?? '',
      currentLocation: GeoLocation.fromMap(
        map['currentLocation'] as Map<String, dynamic>?,
      ),
      rating: Rating.fromMap(map['rating'] as Map<String, dynamic>?),
      isAvailable: map['isAvailable'] as bool? ?? true,
      services: ((map['services'] as List<dynamic>?) ?? [])
          .map((s) => ServiceTypeX.fromString(s as String))
          .toSet(),
    );
  }

  AssistanceProvider copyWith({
    String? name,
    String? profileImagePath,
    GeoLocation? currentLocation,
    Rating? rating,
    Set<ServiceType>? services,
    bool? isAvailable,
  }) {
    return AssistanceProvider(
      uid: uid,
      phoneNumber: phoneNumber,
      name: name ?? this.name,
      profileImagePath: profileImagePath ?? this.profileImagePath,
      currentLocation: currentLocation ?? this.currentLocation,
      rating: rating ?? this.rating,
      services: services ?? this.services,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'phoneNumber': phoneNumber,
    'name': name,
    'userType': userType.name,
    'profileImagePath': profileImagePath,
    'currentLocation': currentLocation.toMap(),
    'rating': rating.toMap(),
    'services': services.map((s) => s.name).toList(),
    'isAvailable': isAvailable,
  };
}

// ============================================================
// Factory: build the correct subtype from stored data
// ============================================================

AppUser userFromMap(String uid, Map<String, dynamic> map) {
  final type = UserTypeX.fromString(map['userType'] as String);
  return switch (type) {
    UserType.driver => Driver.fromMap(uid, map),
    UserType.assistanceProvider => AssistanceProvider.fromMap(uid, map),
  };
}
