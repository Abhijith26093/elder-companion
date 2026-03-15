import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'caregiver_dashboard.dart';
import 'login_screen.dart';
import 'profile_check_wrapper.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  String? _userRole;
  bool _isLoadingRole = true;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('user_role');
      _isLoadingRole = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // StreamBuilder listens to the authentication state changes
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // If the connection is waiting, show a loading indicator.
        if (snapshot.connectionState == ConnectionState.waiting ||
            _isLoadingRole) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If data is present and the user is not null, they are signed in.
        if (snapshot.hasData && snapshot.data != null) {
          // User is signed in. Route based on role.
          if (_userRole == 'caregiver') {
            return const CaregiverDashboard();
          } else {
            // Default to Elder flow if role is elder or null/unknown
            return const ProfileCheckWrapper();
          }
        } else {
          return LoginScreen(role: _userRole ?? 'elder');
        }
      },
    );
  }
}
