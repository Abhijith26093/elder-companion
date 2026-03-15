import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'otp_verification_screen.dart';

class OTPScreen extends StatelessWidget {
  const OTPScreen({
    super.key,
    required this.verificationId,
  });

  final String verificationId;

  @override
  Widget build(BuildContext context) {
    return OtpVerificationScreen(
      title: 'Enter the SMS code',
      subtitle: 'Verify the OTP you received by SMS.',
      initialSession: AuthOtpSession(
        channel: AuthChannel.phone,
        identifier: '',
        destinationHint: 'SMS',
        verificationId: verificationId,
      ),
      onVerify: AuthService.instance.verifyPhoneOtp,
      onResend: (session) async => session,
    );
  }
}
