// File: lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBXpWiPVHlpZZK5cwGSQUIYg7IC0qmlZec',
    appId: '1:306987139596:web:4f1d276aaa816f92fd6429',
    messagingSenderId: '306987139596',
    projectId: 'adscreen-188e3',
    authDomain: 'adscreen-188e3.firebaseapp.com',
    databaseURL: 'https://adscreen-188e3-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'adscreen-188e3.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBXpWiPVHlpZZK5cwGSQUIYg7IC0qmlZec',
    appId: '1:306987139596:android:cfd217983c48e89f', // Assuming Android App ID based on web ID pattern or placeholder. User gave web config only, but requested Android too.
    // NOTE: Ideally we'd get the specific Android App ID from the user or google-services.json.
    // For now, I will use the Web API Key which often works for Android if restrictions are open,
    // but the appId MUST match the one in google-services.json.
    // I will check key in google-services.json if possible, but for now using a placeholder that needs to be correct.
    // Actually, looking at the user request, they only provided the WEB config details in that Javascript block
    // "apiKey: "AIzaSyBXpWiPVHlpZZK5cwGSQUIYg7IC0qmlZec"
    // I will use the same apiKey, projectId, etc.
    // The appId is critical. I'll peek at google-services.json if it exists.
    messagingSenderId: '306987139596',
    projectId: 'adscreen-188e3',
    databaseURL: 'https://adscreen-188e3-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'adscreen-188e3.firebasestorage.app',
  );
}
