import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../entities/app_user.dart';
import '../home/home_page.dart';
import 'screens/complete_profile_page.dart';

/// After a successful sign-in, checks whether this user already has
/// a profile in Firestore. If yes, routes to their role's home page.
/// If no, sends them to CompleteProfilePage to finish signup.
Future<void> routeAfterAuth(
  BuildContext context,
  String uid,
  String phoneNumber,
) async {
  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .get();

  if (!context.mounted) return;

  if (doc.exists) {
    final user = AppUser.fromMap(uid, doc.data()!);
    _goToRoleHome(context, user);
  } else {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CompleteProfilePage(uid: uid, phoneNumber: phoneNumber),
      ),
    );
  }
}

void _goToRoleHome(BuildContext context, AppUser user) {
  Widget destination;

  switch (user.role) {
    case UserRole.driver:
      destination = HomePage(userName: user.name);
      break;
    case UserRole.mechanic:
      // TODO: replace with your real MechanicHomePage once it exists.
      destination = Scaffold(
        appBar: AppBar(title: const Text('Mechanic home')),
        body: Center(child: Text('Welcome, ${user.name}!')),
      );
      break;
  }

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => destination),
    (route) => false,
  );
}
