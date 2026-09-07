import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_user.dart';
import 'screens/complete_profile_page.dart';

/// After a successful sign-in, checks whether this user already has
/// a profile in Firestore. If yes, routes to their role's home page.
/// If no, sends them to CompleteProfilePage to finish signup.
Future<void> routeAfterAuth(BuildContext context, String uid, String phoneNumber) async {
  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

  if (!context.mounted) return;

  if (doc.exists) {
    final user = AppUser.fromMap(uid, doc.data()!);
    _goToRoleHome(context, user.role);
  } else {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CompleteProfilePage(uid: uid, phoneNumber: phoneNumber),
      ),
    );
  }
}

void _goToRoleHome(BuildContext context, UserRole role) {
  // TODO: replace these placeholders with your real
  // DriverHomePage / MechanicHomePage once they exist.
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('${role.name} home')),
        body: Center(child: Text('Welcome, ${role.name}!')),
      ),
    ),
    (route) => false,
  );
}
