import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'entities/app_user.dart';
import 'features/auth/screens/complete_profile_page.dart';
import 'features/auth/screens/login_page.dart';
import 'features/home/home_page.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roadside Assistance',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 234, 5, 5),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginPage();
        }

        return _AuthenticatedRoute(uid: user.uid);
      },
    );
  }
}

class _AuthenticatedRoute extends StatelessWidget {
  final String uid;

  const _AuthenticatedRoute({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        if (snapshot.hasError) {
          return _ErrorScreen(message: snapshot.error.toString());
        }

        final doc = snapshot.data;
        if (doc == null || !doc.exists) {
          return CompleteProfilePage(
            uid: uid,
            phoneNumber: FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
          );
        }

        final user = AppUser.fromMap(uid, doc.data()!);
        return _buildRoleHome(user);
      },
    );
  }

  Widget _buildRoleHome(AppUser user) {
    switch (user.role) {
      case UserRole.driver:
        return HomePage(userName: user.name);
      case UserRole.mechanic:
        return Scaffold(
          appBar: AppBar(title: const Text('Mechanic home')),
          body: Center(child: Text('Welcome, ${user.name}!')),
        );
    }
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _ErrorScreen extends StatelessWidget {
  final String message;

  const _ErrorScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Unable to load your account.\n$message',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
