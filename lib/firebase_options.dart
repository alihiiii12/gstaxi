import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase config. Android is ready; iOS needs GoogleService-Info.plist values.
class DefaultFirebaseOptions {
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCCcZ7ArFNRkJ74Bjsw6WzRIGok4ppI3Xg',
    appId: '1:758178660470:android:1cf385d12c3c7115c71f57',
    messagingSenderId: '758178660470',
    projectId: 'syriataxi-f46d3',
    storageBucket: 'syriataxi-f46d3.firebasestorage.app',
  );

  /// iOS — املأ apiKey و appId من GoogleService-Info.plist بعد إنشاء تطبيق iOS في Firebase.
  /// انظر: ios_mac_guide/FIREBASE_IOS_AR.md
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '758178660470',
    projectId: 'syriataxi-f46d3',
    storageBucket: 'syriataxi-f46d3.firebasestorage.app',
    iosBundleId: 'com.syriataxi.syriataxi',
  );

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return android;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
        return android;
      default:
        return android;
    }
  }

  static bool get isConfigured {
    final opts = currentPlatform;
    return opts.projectId.isNotEmpty &&
        opts.apiKey.isNotEmpty &&
        opts.appId.isNotEmpty;
  }
}
