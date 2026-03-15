import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static FirebaseOptions get web => FirebaseOptions(
        apiKey: _requireEnv('FIREBASE_WEB_API_KEY'),
        appId: _requireEnv('FIREBASE_WEB_APP_ID'),
        messagingSenderId: _requireEnv('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: _requireEnv('FIREBASE_PROJECT_ID'),
        authDomain: _requireEnv('FIREBASE_WEB_AUTH_DOMAIN'),
        storageBucket: _requireEnv('FIREBASE_STORAGE_BUCKET'),
        measurementId: _requireEnv('FIREBASE_WEB_MEASUREMENT_ID'),
      );

  static FirebaseOptions get android => FirebaseOptions(
        apiKey: _requireEnv('FIREBASE_ANDROID_API_KEY'),
        appId: _requireEnv('FIREBASE_ANDROID_APP_ID'),
        messagingSenderId: _requireEnv('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: _requireEnv('FIREBASE_PROJECT_ID'),
        storageBucket: _requireEnv('FIREBASE_STORAGE_BUCKET'),
      );

  static FirebaseOptions get ios => FirebaseOptions(
        apiKey: _requireEnv('FIREBASE_IOS_API_KEY'),
        appId: _requireEnv('FIREBASE_IOS_APP_ID'),
        messagingSenderId: _requireEnv('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: _requireEnv('FIREBASE_PROJECT_ID'),
        storageBucket: _requireEnv('FIREBASE_STORAGE_BUCKET'),
        iosBundleId: _requireEnv('FIREBASE_IOS_BUNDLE_ID'),
      );

  static FirebaseOptions get macos => FirebaseOptions(
        apiKey: _requireEnv('FIREBASE_MACOS_API_KEY'),
        appId: _requireEnv('FIREBASE_MACOS_APP_ID'),
        messagingSenderId: _requireEnv('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: _requireEnv('FIREBASE_PROJECT_ID'),
        storageBucket: _requireEnv('FIREBASE_STORAGE_BUCKET'),
        iosBundleId: _requireEnv('FIREBASE_MACOS_BUNDLE_ID'),
      );

  static FirebaseOptions get windows => FirebaseOptions(
        apiKey: _requireEnv('FIREBASE_WINDOWS_API_KEY'),
        appId: _requireEnv('FIREBASE_WINDOWS_APP_ID'),
        messagingSenderId: _requireEnv('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: _requireEnv('FIREBASE_PROJECT_ID'),
        authDomain: _requireEnv('FIREBASE_WINDOWS_AUTH_DOMAIN'),
        storageBucket: _requireEnv('FIREBASE_STORAGE_BUCKET'),
        measurementId: _requireEnv('FIREBASE_WINDOWS_MEASUREMENT_ID'),
      );

  static String _requireEnv(String key) {
    final value = dotenv.env[key];
    if (value == null || value.trim().isEmpty) {
      throw StateError('Missing required .env value: $key');
    }
    return value.trim();
  }
}
