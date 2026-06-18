import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
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

  assert(
    _supabaseUrl.isNotEmpty && _supabasePublishableKey.isNotEmpty,
    'Missing Supabase config. Run with: flutter run --dart-define-from-file=.env.json',
  );

  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  final rcKey = Platform.isIOS ? _rcAppleKey : _rcGoogleKey;
  if (rcKey.isNotEmpty) {
    await Purchases.configure(PurchasesConfiguration(rcKey));
    rcConfigured = true;
  }

  runApp(const ProviderScope(child: AppShell()));

  // Push init is intentionally unawaited — getToken() hangs on simulator
  // (no APNs) and should never block app launch on real devices either.
  PushNotificationService.initialize();
}
