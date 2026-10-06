import '../../../entities/app_user.dart';

class ProviderService {
  final String id;
  final String providerUid;
  final ServiceType serviceType;
  final String name;
  final String vehicleTypes;
  final String plateNumber;
  final String location;
  final GeoLocation? locationGeo;
  final String details;
  final bool isActive;

  const ProviderService({
    required this.id,
    required this.providerUid,
    required this.serviceType,
    required this.name,
    required this.vehicleTypes,
    required this.plateNumber,
    required this.location,
    this.locationGeo,
    required this.details,
    this.isActive = true,
  });

  ProviderService copyWith({
    String? id,
    String? providerUid,
    ServiceType? serviceType,
    String? name,
    String? vehicleTypes,
    String? plateNumber,
    String? location,
    GeoLocation? locationGeo,
    String? details,
    bool? isActive,
  }) {
    return ProviderService(
      id: id ?? this.id,
      providerUid: providerUid ?? this.providerUid,
      serviceType: serviceType ?? this.serviceType,
      name: name ?? this.name,
      vehicleTypes: vehicleTypes ?? this.vehicleTypes,
      plateNumber: plateNumber ?? this.plateNumber,
      location: location ?? this.location,
      locationGeo: locationGeo ?? this.locationGeo,
      details: details ?? this.details,
      isActive: isActive ?? this.isActive,
    );
  }

  factory ProviderService.fromMap(String id, Map<String, dynamic> map) {
    return ProviderService(
      id: id,
      providerUid: map['providerUid'] as String? ?? '',
      serviceType: ServiceTypeX.fromString(
        map['serviceType'] as String? ?? ServiceType.towTruck.name,
      ),
      name: map['name'] as String? ?? '',
      vehicleTypes: map['vehicleTypes'] as String? ?? '',
      plateNumber: map['plateNumber'] as String? ?? '',
      location: map['location'] as String? ?? '',
      locationGeo: map['locationGeo'] != null
          ? GeoLocation.fromMap(map['locationGeo'] as Map<String, dynamic>?)
          : null,
      details: map['details'] as String? ?? '',
      isActive: map['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'providerUid': providerUid,
    'serviceType': serviceType.name,
    'name': name,
    'vehicleTypes': vehicleTypes,
    'plateNumber': plateNumber,
    'location': location,
    'locationGeo': locationGeo?.toMap(),
    'details': details,
    'isActive': isActive,
  };

  String get displayType => switch (serviceType) {
    ServiceType.towTruck => 'Vehicle Tow',
    ServiceType.mechanic => 'Mechanic',
    ServiceType.fuelDelivery => 'Fuel Delivery',
    ServiceType.flatTireChange => 'Flat Tire Change',
    ServiceType.batteryBoost => 'Battery Boost',
  };
}
