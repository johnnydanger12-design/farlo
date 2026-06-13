// ⚠️  STUB — Replace by running:
//   dart pub global activate flutterfire_cli
//   flutterfire configure
//
// flutterfire configure will overwrite this file with real values from your
// Firebase project and download google-services.json + GoogleService-Info.plist.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web not supported');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Unsupported platform: $defaultTargetPlatform');
    }
  }



  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA2EMaJfDkWqIkQ31zhJUWR_GItv6zCYwE',
    appId: '1:469153137408:android:8183147264e9c75568e9e5',
    messagingSenderId: '469153137408',
    projectId: 'good-truck-finder',
    storageBucket: 'good-truck-finder.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBUVH-fEgaJfLZxl6RN7GPGLGCkwJODZME',
    appId: '1:469153137408:ios:69fe81a9056ba8d668e9e5',
    messagingSenderId: '469153137408',
    projectId: 'good-truck-finder',
    storageBucket: 'good-truck-finder.firebasestorage.app',
    iosBundleId: 'com.goodtruckfinder.goodTruckFinder',
  );
}
