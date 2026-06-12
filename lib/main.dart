import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_shell.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _rcAppleKey = String.fromEnvironment('REVENUECAT_APPLE_KEY');
const _rcGoogleKey = String.fromEnvironment('REVENUECAT_GOOGLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  assert(
    _supabaseUrl.isNotEmpty && _supabasePublishableKey.isNotEmpty,
    'Missing Supabase config. Run with: flutter run --dart-define-from-file=.env.json',
  );

  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );

  final rcKey = Platform.isIOS ? _rcAppleKey : _rcGoogleKey;
  if (rcKey.isNotEmpty) {
    await Purchases.configure(PurchasesConfiguration(rcKey));
  }

  runApp(const ProviderScope(child: AppShell()));
}
