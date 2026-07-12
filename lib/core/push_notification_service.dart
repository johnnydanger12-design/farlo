import 'dart:io';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/models/app_user.dart';
import '../router.dart';

// Top-level handler required by Firebase for background messages.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // No-op: the OS notification is already shown by FCM when the app is in
  // the background or terminated. Nothing extra needed here.
}

class PushNotificationService {
  PushNotificationService._();

  // ── Cold-start deep-link buffer ─────────────────────────────────────────────
  // getInitialMessage() can resolve before the router is built or before auth
  // loads. We buffer the message and drain it only once both are ready so that
  // the redirect logic doesn't override the intended deep-link destination.

  static RemoteMessage? _pendingMessage;
  static bool _isOwner = false;
  static bool _authResolved = false;

  // Called from router.dart immediately after _sharedRouter is assigned.
  static void onRouterReady() {
    if (_authResolved) _drainPending();
  }

  // Called from app_shell.dart whenever the auth state settles (user or null).
  static void onAuthResolved(AppUser? user) {
    _isOwner = user?.isOwner ?? false;
    _authResolved = user != null;
    _drainPending();

    // Retry token registration now that we have a resolved auth state.
    // Root cause of push tokens never getting saved: initialize() fetches
    // and stores the token once, unawaited, immediately after runApp() --
    // completely independent of login. _storeToken() silently no-ops if
    // auth.currentUser is null at that exact moment (e.g. a brand-new
    // signup, where nobody's logged in yet when initialize() runs). The
    // only other path that could retry is onTokenRefresh, which only fires
    // on rare FCM token rotation, not on login -- so without this, a
    // user's very first session could go permanently unregistered unless
    // FCM happens to rotate their token at some later, unpredictable time.
    // This listener already fires on every auth transition (confirmed via
    // app_shell.dart's ref.listen(authProvider, ...)), including right
    // after a fresh signup/login, so it's the right place to close the gap.
    if (user != null) _registerCurrentToken();
  }

  static Future<void> _registerCurrentToken() async {
    // Root cause of push_tokens being permanently empty, confirmed via a
    // real device log (2026-07-12): getToken() requires the native APNs
    // device token to already be set, but that handshake with Apple's
    // servers doesn't complete synchronously with requestPermission()
    // resolving -- calling getToken() immediately after throws
    // [firebase_messaging/apns-token-not-set] on every single call, not
    // just occasionally. Poll for the APNs token first, with a bounded
    // retry budget, before ever calling getToken().
    if (Platform.isIOS) {
      String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      var attempts = 0;
      while (apnsToken == null && attempts < 10) {
        await Future.delayed(const Duration(seconds: 1));
        apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        attempts++;
      }
      if (apnsToken == null) {
        debugPrint('PushNotificationService: APNS token never arrived after $attempts retries');
        return;
      }
    }

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (e, st) {
      debugPrint('PushNotificationService: getToken() failed: $e');
      await FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'push token getToken() failed',
        fatal: false,
      );
      return;
    }
    if (token == null) return;
    await _storeToken(token);
  }

  static void _drainPending() {
    final msg = _pendingMessage;
    if (msg != null && sharedRouter != null) {
      _pendingMessage = null;
      _handleNotificationTap(msg);
    }
  }

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

  static Future<void> sendShiftAssigned(String shiftId) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-shift-notification',
        body: {'action': 'shift_assigned', 'shift_id': shiftId},
      );
    } catch (e) {
      debugPrint('Failed to send shift_assigned notification: $e');
    }
  }

  static Future<void> sendShiftCorrected(String shiftId) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-shift-notification',
        body: {'action': 'shift_corrected', 'shift_id': shiftId},
      );
    } catch (e) {
      debugPrint('Failed to send shift_corrected notification: $e');
    }
  }

  static Future<void> sendShiftResponse(String shiftId) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-shift-notification',
        body: {'action': 'shift_response', 'shift_id': shiftId},
      );
    } catch (e) {
      debugPrint('Failed to send shift_response notification: $e');
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

    // Register current token (throws on iOS simulator — safe to ignore).
    // Also retried from onAuthResolved() -- see that method's doc comment
    // for why a single attempt here isn't sufficient on its own.
    await _registerCurrentToken();

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

    // Tap routing: app in background → user taps notification banner
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Tap routing: app was terminated → user taps notification to launch.
    // _handleNotificationTap buffers the message if the router or auth aren't
    // ready yet; it's drained by onRouterReady() + onAuthResolved() in order.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial);
  }

  static void _handleNotificationTap(RemoteMessage message) {
    final router = sharedRouter;
    if (router == null) {
      // Router not yet ready — buffer until onRouterReady() + onAuthResolved() both fire.
      _pendingMessage = message;
      return;
    }

    final type = message.data['type'] as String?;
    switch (type) {
      // ── Consumer-side booking notifications ───────────────────────────────
      // These are sent to the person who made the booking. If that person is
      // also an owner-role user, the consumer shell would redirect them to
      // /dashboard, so we send owner-role users to their notifications inbox.
      case 'booking_accepted':
      case 'booking_declined':
      case 'booking_cancelled_by_owner':
      case 'estimate_sent':
      case 'deposit_requested':
      case 'invoice_sent':
        router.go(_isOwner ? '/owner-notifications' : '/notifications/my-requests');
      // ── Owner-side booking notifications ──────────────────────────────────
      case 'booking_created':
      case 'booking_cancelled_by_consumer':
      case 'estimate_responded':
      case 'deposit_paid':
      case 'invoice_paid':
        router.go('/owner-bookings');
      case 'new_message':
        final recipientIsOwner = message.data['recipient_is_owner'] == 'true';
        router.go(recipientIsOwner ? '/owner-bookings' : '/notifications/my-requests');
      // ── Announcements (fan-out to all followers) ───────────────────────────
      case 'announcement':
        router.go(_isOwner ? '/owner-notifications' : '/notifications');
      // ── Owner-side order notifications ────────────────────────────────────
      case 'order_placed':
      case 'order_cancelled':
        router.go('/dashboard/orders');
      // ── Consumer-side order notifications ─────────────────────────────────
      case 'order_accepted':
      case 'order_ready':
      case 'order_declined':
        router.go(_isOwner ? '/owner-notifications' : '/notifications/my-orders');
      // ── Shift notifications ──────────────────────────────────────────────────
      // shift_assigned / shift_corrected → employee lands on map where
      // EmployeeGoLiveCard lets them tap into their dashboard to accept/decline.
      // shift_response → owner back to dashboard to see the response.
      case 'shift_assigned':
      case 'shift_corrected':
        router.go('/map');
      case 'shift_response':
        router.go('/dashboard');
      // ── Open-check notification ──────────────────────────────────────────────
      case 'open_check':
        router.go('/dashboard');
      default:
        break;
    }
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
