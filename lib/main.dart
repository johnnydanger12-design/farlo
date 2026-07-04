import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_shell.dart';
import 'core/push_notification_service.dart';
import 'core/rc_config.dart';
import 'firebase_options.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _rcAppleKey = String.fromEnvironment('REVENUECAT_APPLE_KEY');
const _rcGoogleKey = String.fromEnvironment('REVENUECAT_GOOGLE_KEY');
const _stripePublishableKey = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_stripePublishableKey.isNotEmpty) {
    Stripe.publishableKey = _stripePublishableKey;
    await Stripe.instance.applySettings();
  }

  // A plain `assert` here is stripped in release builds, so a misconfigured
  // release archive (e.g. built without --dart-define-from-file) would launch
  // fine and only fail deep inside auth calls with no visible cause — which is
  // exactly what happened in the 1.0.0+4 App Store submission. Fail loudly in
  // every build mode instead.
  if (_supabaseUrl.isEmpty || _supabasePublishableKey.isEmpty) {
    throw StateError(
      'Missing Supabase config. Build with: flutter build ipa --dart-define-from-file=.env.json',
    );
  }

  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  // Crash visibility gap: two of three prior App Store rejections were only
  // diagnosable because Apple happened to attach screenshots — there was no
  // server-side signal at all if the app crashed on a reviewer's or user's
  // device (app-store-review.md Finding 8.1). Disabled in debug so local
  // development crashes don't pollute the production Crashlytics dashboard.
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  final rcKey = Platform.isIOS ? _rcAppleKey : _rcGoogleKey;
  if (rcKey.isNotEmpty) {
    try {
      await Purchases.configure(PurchasesConfiguration(rcKey)).timeout(const Duration(seconds: 10));
      rcConfigured = true;
    } catch (_) {
      // Don't let a stuck RevenueCat init block app launch — subscription
      // features will simply be unavailable until the next app start.
    }
  }

  runApp(const ProviderScope(child: AppShell()));

  // Push init is intentionally unawaited — getToken() hangs on simulator
  // (no APNs) and should never block app launch on real devices either.
  PushNotificationService.initialize();
}
