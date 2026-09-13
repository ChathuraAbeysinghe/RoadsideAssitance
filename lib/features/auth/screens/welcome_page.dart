import 'package:flutter/material.dart';

import '../../../entities/app_user.dart';
import 'login_page.dart';

/// First screen shown to a signed-out user. Lets them pick which role
/// they're signing up/logging in as before phone verification, so that
/// once OTP succeeds, a brand-new account lands on the correct
/// complete-profile page. Existing users are routed to their real,
/// already-stored role regardless of what they tap here.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  void _goToLogin(BuildContext context, UserType intendedRole) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LoginPage(intendedRole: intendedRole)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Top hero image.
            SizedBox(
              height: 350,
              width: double.infinity,
              child: Image.asset(
                'assets/images/welcome.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey.shade300,
                  child: Icon(
                    Icons.build_circle_outlined,
                    size: 80,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      height: 80,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.local_shipping,
                        size: 80,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 0),
                    const Text(
                      'Roadside Assistant',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 40),
                    const Text(
                      'Peace of mind behind\nthe wheel',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 60),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => _goToLogin(context, UserType.driver),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE30613),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: const Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () =>
                          _goToLogin(context, UserType.assistanceProvider),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          style: TextStyle(fontSize: 14, color: Colors.black87),
                          children: [
                            TextSpan(text: 'Want to earn? '),
                            TextSpan(
                              text: 'Register as a Assistant',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color.fromARGB(255, 246, 1, 1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
