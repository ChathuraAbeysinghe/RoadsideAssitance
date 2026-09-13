import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'entities/app_user.dart';
import 'features/auth/screens/welcome_page.dart';
import 'features/home/home_page.dart';
import 'features/home/assistance_provider_home_page.dart';
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
          return const WelcomePage();
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
          // Signed in with Firebase Auth but never finished the
          // complete-profile step (e.g. app was closed mid-signup).
          // There's no intendedRole available here, so send them back
          // to the Welcome screen to pick a role and go through
          // complete-profile again.
          return const WelcomePage();
        }

        // userFromMap inspects the stored `userType` and returns either
        // a Driver or an AssistanceProvider instance.
        final user = userFromMap(uid, doc.data()!);
        return _buildRoleHome(user);
      },
    );
  }

  Widget _buildRoleHome(AppUser user) {
    switch (user.userType) {
      case UserType.driver:
        return HomePage(
          userName: user.name,
          profileImagePath: user.profileImagePath,
        );
      case UserType.assistanceProvider:
        return AssistanceProviderHomePage(
          userName: user.name,
          profileImagePath: user.profileImagePath,
        );
    }
  }
}

class _LoadingScreen extends StatefulWidget {
  const _LoadingScreen();

  @override
  State<_LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<_LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    final scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: fadeAnimation,
          child: ScaleTransition(
            scale: scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 150,
                  height: 150,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.local_shipping,
                    size: 100,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 24),
                const Text(
                  'Roadside Assistance',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
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
