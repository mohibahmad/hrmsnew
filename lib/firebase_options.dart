

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;


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
    apiKey: 'AIzaSyDlw3flE_8JrtFX2uAbAtBpi_B89J6p8Ac',
    appId: '1:343295414565:web:56b1edf40047b945e70acc',
    messagingSenderId: '343295414565',
    projectId: 'businesscard-6f5c4',
    authDomain: 'businesscard-6f5c4.firebaseapp.com',
    databaseURL: 'https://businesscard-6f5c4-default-rtdb.firebaseio.com',
    storageBucket: 'businesscard-6f5c4.firebasestorage.app',
    measurementId: 'G-HFCNS1QQPS',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBS8UxX-Ctr8eqMjfeeNRK1iDQDdFr3PtE',
    appId: '1:343295414565:android:c86c6faf16f650a6e70acc',
    messagingSenderId: '343295414565',
    projectId: 'businesscard-6f5c4',
    databaseURL: 'https://businesscard-6f5c4-default-rtdb.firebaseio.com',
    storageBucket: 'businesscard-6f5c4.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD3nXfQrlg6GdGxLkBPZD0DoY7-rgF7ZSM',
    appId: '1:343295414565:ios:723a81a3aeebe655e70acc',
    messagingSenderId: '343295414565',
    projectId: 'businesscard-6f5c4',
    databaseURL: 'https://businesscard-6f5c4-default-rtdb.firebaseio.com',
    storageBucket: 'businesscard-6f5c4.firebasestorage.app',
    androidClientId: '343295414565-jn4gu5u7ia32tm5if028ucke6325q15l.apps.googleusercontent.com',
    iosClientId: '343295414565-vr2noki0jr0fujntddpf8p8b5fa12p52.apps.googleusercontent.com',
    iosBundleId: 'com.example.hrms',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyD3nXfQrlg6GdGxLkBPZD0DoY7-rgF7ZSM',
    appId: '1:343295414565:ios:723a81a3aeebe655e70acc',
    messagingSenderId: '343295414565',
    projectId: 'businesscard-6f5c4',
    databaseURL: 'https://businesscard-6f5c4-default-rtdb.firebaseio.com',
    storageBucket: 'businesscard-6f5c4.firebasestorage.app',
    androidClientId: '343295414565-jn4gu5u7ia32tm5if028ucke6325q15l.apps.googleusercontent.com',
    iosClientId: '343295414565-vr2noki0jr0fujntddpf8p8b5fa12p52.apps.googleusercontent.com',
    iosBundleId: 'com.example.hrms',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDlw3flE_8JrtFX2uAbAtBpi_B89J6p8Ac',
    appId: '1:343295414565:web:79666ebfc815a41ce70acc',
    messagingSenderId: '343295414565',
    projectId: 'businesscard-6f5c4',
    authDomain: 'businesscard-6f5c4.firebaseapp.com',
    databaseURL: 'https://businesscard-6f5c4-default-rtdb.firebaseio.com',
    storageBucket: 'businesscard-6f5c4.firebasestorage.app',
    measurementId: 'G-GZH9PPB9VZ',
  );

}