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
  final String profileImagePath;

  AppUser({
    required this.uid,
    required this.phoneNumber,
    required this.name,
    required this.role,
    this.profileImagePath = '',
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      phoneNumber: map['phoneNumber'] as String? ?? '',
      name: map['name'] as String? ?? '',
      role: UserRoleX.fromString(map['role'] as String),
      profileImagePath: map['profileImagePath'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'phoneNumber': phoneNumber,
      'name': name,
      'role': role.name,
      'profileImagePath': profileImagePath,
    };
  }
}
