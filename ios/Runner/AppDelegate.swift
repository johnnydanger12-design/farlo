import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Root cause of push notifications never registering, found 2026-07-12: a
  // known FlutterFire bug (firebase/flutterfire#12244, flutter/flutter#185048)
  // where registering plugins via FlutterImplicitEngineDelegate's
  // didInitializeImplicitFlutterEngine (the newer Scene-based pattern) causes
  // FLTFirebaseMessagingPlugin to never correctly wire itself as
  // Messaging.messaging().delegate -- confirmed on this exact app via a bare
  // native UIKit reproduction that reliably gets a real APNs token under
  // identical signing/entitlement conditions where Farlo never received even
  // a native didRegisterForRemoteNotificationsWithDeviceToken callback.
  // Fixed by registering plugins synchronously in didFinishLaunchingWithOptions
  // instead -- the traditional pattern Firebase's SDK is built around.
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
