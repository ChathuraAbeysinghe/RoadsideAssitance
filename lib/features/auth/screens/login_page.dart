import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../phone_auth_datasource.dart';
import '../auth_router_helper.dart';
import 'otp_verification.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final PhoneAuthDataSource _authDataSource = PhoneAuthDataSource();

  String? _completePhoneNumber;
  bool _isLoading = false;

  Future<void> _onContinue() async {
    if (_completePhoneNumber == null || _completePhoneNumber!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your mobile number')),
      );
      return;
    }

    setState(() => _isLoading = true);

    await _authDataSource.sendOtp(
      phoneNumber: _completePhoneNumber!,
      onCodeSent: () {
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OtpVerification(
              phoneNumber: _completePhoneNumber!,
              authDataSource: _authDataSource,
            ),
          ),
        );
      },
      onAutoVerified: (userCredential) async {
        if (!mounted) return;
        final uid = userCredential.user!.uid;
        await routeAfterAuth(context, uid, _completePhoneNumber!);
      },
      onFailed: (message) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.chevron_left),
                style: IconButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: const CircleBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  height: 100,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.local_shipping,
                    size: 80,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Please Enter Your Mobile Number',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'We will send you a verification code to this number',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              IntlPhoneField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black, width: 2),
                  ),
                ),
                initialCountryCode: 'LK',
                onChanged: (phone) {
                  _completePhoneNumber = phone.completeNumber;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE30613),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  children: [
                    const TextSpan(
                      text: 'By proceeding, you acknowledge that you have read and agreed to our ',
                    ),
                    TextSpan(
                      text: 'Terms of Services',
                      style: const TextStyle(color: Color(0xFFE30613)),
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: const TextStyle(color: Color(0xFFE30613)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
