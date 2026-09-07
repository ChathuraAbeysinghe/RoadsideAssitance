enum UserRole { driver, mechanic }

extension UserRoleX on UserRole {
  String get name {
    switch (this) {
      case UserRole.driver:
        return 'driver';
      case UserRole.mechanic:
        return 'mechanic';
    }
  }

  static UserRole fromString(String value) {
    switch (value) {
      case 'driver':
        return UserRole.driver;
      case 'mechanic':
        return UserRole.mechanic;
      default:
        throw ArgumentError('Unknown role: $value');
    }
  }
}

class AppUser {
  final String uid;
  final String phoneNumber;
  final String name;
  final UserRole role;

  AppUser({
    required this.uid,
    required this.phoneNumber,
    required this.name,
    required this.role,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      phoneNumber: map['phoneNumber'] as String? ?? '',
      name: map['name'] as String? ?? '',
      role: UserRoleX.fromString(map['role'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'phoneNumber': phoneNumber,
      'name': name,
      'role': role.name,
    };
  }
}
