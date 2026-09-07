import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../phone_auth_datasource.dart';
import '../auth_router_helper.dart';

class OtpVerification extends StatefulWidget {
  final String phoneNumber;
  final PhoneAuthDataSource authDataSource;

  const OtpVerification({
    super.key,
    required this.phoneNumber,
    required this.authDataSource,
  });

  @override
  State<OtpVerification> createState() => _OtpVerificationState();
}

class _OtpVerificationState extends State<OtpVerification> {
  String _enteredCode = '';
  bool _isLoading = false;
  int _secondsLeft = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    _secondsLeft = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft == 0) {
        timer.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String get _formattedTime {
    final minutes = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _onResend() async {
    setState(() => _isLoading = true);
    await widget.authDataSource.sendOtp(
      phoneNumber: widget.phoneNumber,
      onCodeSent: () {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _startResendTimer();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Code resent')));
      },
      onAutoVerified: (userCredential) async {
        if (!mounted) return;
        await routeAfterAuth(
          context,
          userCredential.user!.uid,
          widget.phoneNumber,
        );
      },
      onFailed: (message) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }

  Future<void> _onVerify() async {
    if (_enteredCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the 6-digit code')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userCredential = await widget.authDataSource.verifyOtp(
        _enteredCode,
      );
      if (!mounted) return;
      await routeAfterAuth(
        context,
        userCredential.user!.uid,
        widget.phoneNumber,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid code. Please try again.')),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.chevron_left),
                  style: IconButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: const CircleBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Logo
              Image.asset(
                'assets/images/logo.png',
                height: 110,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.local_shipping,
                  size: 90,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 32),

              // Title
              const Text(
                'Verify via Message',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              // Subtitle: "Please enter 6 Digit OTP sent via SMS to"
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                  children: const [
                    TextSpan(text: 'Please enter 6 Digit OTP sent via '),
                    TextSpan(
                      text: 'SMS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    TextSpan(text: ' to'),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              // Phone number + Change link
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.phoneNumber,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Text(
                      'Change',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 43, 113, 182),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // OTP input boxes
              MaterialPinField(
                length: 6,
                onCompleted: (pin) {
                  _enteredCode = pin;
                },
                onChanged: (value) {
                  _enteredCode = value;
                },
                theme: MaterialPinTheme(
                  shape: MaterialPinShape.outlined,
                  cellSize: const Size(44, 52),
                  spacing: 12,
                  borderRadius: BorderRadius.circular(12),
                  borderColor: Colors.grey.shade400,
                  focusedBorderColor: const Color.fromARGB(255, 0, 0, 0),
                  filledBorderColor: const Color(0xFF969697),
                  fillColor: Colors.white,
                  focusedFillColor: Colors.white,
                  filledFillColor: Colors.white,
                  cursorColor: Colors.black,
                ),
              ),
              const SizedBox(height: 24),

              // Resend row
              _secondsLeft > 0
                  ? RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black,
                        ),
                        children: [
                          const TextSpan(
                            text: "If you didn't receive a code. ",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: 'Resend in $_formattedTime Seconds',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : GestureDetector(
                      onTap: _isLoading ? null : _onResend,
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          style: TextStyle(fontSize: 14, color: Colors.black),
                          children: [
                            TextSpan(
                              text: "Didn't receive a code? ",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text: 'Resend Code',
                              style: TextStyle(
                                color: Color(0xFFE30613),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              const SizedBox(height: 32),

              // Verify button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _onVerify,
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
                          'Verify',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
