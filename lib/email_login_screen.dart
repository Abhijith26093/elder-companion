import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'otp_verification_screen.dart';

class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({
    super.key,
    this.role = 'elder',
  });

  final String role;

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final session = await AuthService.instance.startBackendOtp(
        channel: AuthChannel.email,
        identifier: _emailController.text,
      );
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            title: 'Check your inbox',
            subtitle:
                'We sent a one-time password by email. Enter it below to continue.',
            initialSession: session,
            onVerify: AuthService.instance.verifyBackendOtp,
            onResend: AuthService.instance.resendBackendOtp,
          ),
        ),
      );
    } on AuthFlowException catch (error) {
      _showMessage(error.message, isError: true);
    } catch (_) {
      _showMessage('Unable to send the email OTP.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.orange.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Email OTP Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Email OTP Authentication',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'The backend generates the OTP, stores it in Firestore, and signs the app into Firebase with a custom token after verification.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.black54,
                    ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live email delivery',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text('Send OTPs to any valid email address.'),
                    SizedBox(height: 4),
                    Text('This requires your backend SMTP credentials to be configured.'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  hintText: '22b827@nssce.ac.in',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _sendOtp,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Send Email OTP'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
