import 'package:firebase_auth/firebase_auth.dart';

/// Wraps FirebaseAuth's callback-based phone verification into
/// simple methods the rest of the app can call cleanly.
class PhoneAuthDataSource {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _verificationId;
  int? _resendToken;

  /// Sends an OTP to the given phone number.
  /// [phoneNumber] must be in E.164 format, e.g. "+94771234567".
  ///
  /// Calls [onCodeSent] once the SMS has been sent (so the UI can
  /// navigate to the OTP entry screen).
  /// Calls [onAutoVerified] if Android auto-detects the code and
  /// signs the user in without manual entry.
  /// Calls [onFailed] with a human-readable message if sending fails.
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function() onCodeSent,
    required void Function(UserCredential credential) onAutoVerified,
    required void Function(String message) onFailed,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      forceResendingToken: _resendToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android-only: auto-retrieval succeeded, sign in immediately.
        final userCredential = await _auth.signInWithCredential(credential);
        onAutoVerified(userCredential);
      },
      verificationFailed: (FirebaseAuthException e) {
        onFailed(_mapError(e));
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        onCodeSent();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // Auto-retrieval window closed; keep the verificationId
        // for manual entry, don't treat this as an error.
        _verificationId = verificationId;
      },
    );
  }

  /// Verifies the 6-digit code the user typed in.
  Future<UserCredential> verifyOtp(String smsCode) async {
    if (_verificationId == null) {
      throw StateError('No verification in progress. Call sendOtp first.');
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: smsCode,
    );

    return _auth.signInWithCredential(credential);
  }

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signOut() => _auth.signOut();

  String _mapError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'That phone number looks invalid. Please check and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }
}
