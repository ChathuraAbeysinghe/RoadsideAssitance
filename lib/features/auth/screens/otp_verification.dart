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
                'Enter Verification Code',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a 6-digit code to ${widget.phoneNumber}',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),

              // OTP input boxes (pin_code_fields v9 API)
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
                  borderRadius: BorderRadius.circular(12),
                  borderColor: Colors.grey.shade300,
                  focusedBorderColor: const Color(0xFFE30613),
                  filledBorderColor: Colors.black,
                ),
              ),
              const SizedBox(height: 24),

              Center(
                child: _secondsLeft > 0
                    ? Text(
                        'Resend code in $_secondsLeft s',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      )
                    : TextButton(
                        onPressed: _isLoading ? null : _onResend,
                        child: const Text(
                          'Resend Code',
                          style: TextStyle(
                            color: Color(0xFFE30613),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 32),
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
