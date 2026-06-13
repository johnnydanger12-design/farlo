import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Top-level handler required by Firebase for background messages.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // No-op: the OS notification is already shown by FCM when the app is in
  // the background or terminated. Nothing extra needed here.
}

class PushNotificationService {
  PushNotificationService._();

  static Future<int> sendTruckAnnouncement({
    required String truckId,
    required String title,
    required String message,
  }) async {
    final res = await Supabase.instance.client.functions.invoke(
      'send-truck-announcement',
      body: {'truck_id': truckId, 'title': title, 'message': message},
    );
    return (res.data?['sent'] as int?) ?? 0;
  }

  static Future<void> sendTruckOpenAlert(String truckName) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.functions.invoke(
        'send-booking-notification',
        body: {'action': 'truck_open', 'truck_name': truckName, 'user_id': userId},
      );
    } catch (e) {
      debugPrint('Failed to send truck open alert: $e');
    }
  }

  static Future<void> sendTruckClosedAlert(String truckName) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.functions.invoke(
        'send-booking-notification',
        body: {'action': 'truck_closed', 'truck_name': truckName, 'user_id': userId},
      );
    } catch (e) {
      debugPrint('Failed to send truck closed alert: $e');
    }
  }

  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // Request permission (iOS; Android 13+ also needs this)
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Push notification permission denied');
      return;
    }

    // Register current token
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _storeToken(token);

    // Re-register whenever the token rotates
    FirebaseMessaging.instance.onTokenRefresh.listen(_storeToken);

    // Foreground messages: FCM suppresses banners on iOS when the app is
    // open. Present them as system alerts so the user still sees them.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  static Future<void> _storeToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final platform = Platform.isIOS ? 'ios' : 'android';
    try {
      await Supabase.instance.client.from('push_tokens').upsert(
        {
          'user_id': user.id,
          'platform': platform,
          'token': token,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,platform',
      );
    } catch (e) {
      debugPrint('Failed to store push token: $e');
    }
  }
}
