import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../entities/app_user.dart';
import '../home/home_page.dart';
import '../home/assistance_provider_home_page.dart';
import 'screens/complete_profile_page.dart';
import 'screens/service_provider_complete_profile_page.dart';

/// After a successful sign-in, checks whether this user already has
/// a profile in Firestore.
///
/// - If yes: routes to their real, already-stored role's home page,
///   regardless of what [intendedRole] was picked on the Welcome screen.
/// - If no: this is a brand-new account, so [intendedRole] (chosen on
///   the Welcome screen before login) decides which complete-profile
///   page to send them to.
Future<void> routeAfterAuth(
  BuildContext context,
  String uid,
  String phoneNumber, {
  required UserType intendedRole,
}) async {
  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .get();

  if (!context.mounted) return;

  if (doc.exists) {
    final user = userFromMap(uid, doc.data()!);
    _goToRoleHome(context, user);
  } else {
    _goToCompleteProfile(context, uid, phoneNumber, intendedRole);
  }
}

void _goToCompleteProfile(
  BuildContext context,
  String uid,
  String phoneNumber,
  UserType intendedRole,
) {
  Widget destination;

  switch (intendedRole) {
    case UserType.driver:
      destination = CompleteProfilePage(uid: uid, phoneNumber: phoneNumber);
      break;
    case UserType.assistanceProvider:
      destination = ServiceProviderCompleteProfilePage(
        uid: uid,
        phoneNumber: phoneNumber,
      );
      break;
  }

  Navigator.of(context)
      .pushReplacement(MaterialPageRoute(builder: (_) => destination));
}

void _goToRoleHome(BuildContext context, AppUser user) {
  Widget destination;

  switch (user.userType) {
    case UserType.driver:
      destination = HomePage(
        userName: user.name,
        profileImagePath: user.profileImagePath,
      );
      break;
    case UserType.assistanceProvider:
      final provider = user as AssistanceProvider;
      destination = AssistanceProviderHomePage(
        userName: provider.name,
        profileImagePath: provider.profileImagePath,
      );
      break;
  }

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => destination),
    (route) => false,
  );
}
