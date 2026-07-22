// Mirrors stripe_connect_screen.dart's deep-link-listen + lifecycle-resume
// pattern — Square's OAuth redirect lands on square-oauth-callback (plain
// HTTPS, no custom scheme, same reason Stripe's return_url isn't one
// either), which then 302s into the app via farlo://square-connect with a
// `status` param.
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../providers/pos_integration_provider.dart';

class ConnectSquareScreen extends ConsumerStatefulWidget {
  const ConnectSquareScreen({super.key});

  @override
  ConsumerState<ConnectSquareScreen> createState() => _ConnectSquareScreenState();
}

class _ConnectSquareScreenState extends ConsumerState<ConnectSquareScreen> with WidgetsBindingObserver {
  String _environment = 'production';
  bool _loading = false;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _linkSub = AppLinks().uriLinkStream.listen(_handleDeepLink);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(posIntegrationProvider);
    }
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme != 'farlo' || uri.host != 'square-connect') return;
    final status = uri.queryParameters['status'];
    final message = uri.queryParameters['message'];
    switch (status) {
      case 'success':
        ref.invalidate(posIntegrationProvider);
        if (mounted) {
          context.showSuccess('Square connected!');
          context.pop();
        }
      case 'needs_location':
        if (mounted) context.push('/owner-account/pos-integration/square-location');
      default:
        // Square's raw error text can be long (a JSON error body) — give it
        // a long duration and a manual close so there's actually time to
        // read it, rather than the default 4s auto-dismiss.
        if (mounted) {
          context.showError(
            message ?? 'Could not connect Square.',
            duration: const Duration(seconds: 30),
            showCloseIcon: true,
          );
        }
    }
  }

  Future<void> _connect() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(posIntegrationRepositoryProvider);
      final url = await repo.startSquareOauth(environment: _environment);
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) context.showError(sanitizeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Square'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'Connect your Square account to automatically send Farlo orders to it.',
            style: AppTextStyles.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          // Sandbox is a Square engineering-testing concept, meaningless to
          // a real merchant — every real owner always wants Production, so
          // this picker only exists in debug builds (our own testing),
          // never in what ships to a real business.
          if (kDebugMode) ...[
            DropdownButtonFormField<String>(
              initialValue: _environment,
              decoration: InputDecoration(
                labelText: 'Environment (debug only)',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: const [
                DropdownMenuItem(value: 'production', child: Text('Production')),
                DropdownMenuItem(value: 'sandbox', child: Text('Sandbox')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _environment = val);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Connect with Square',
            onPressed: _loading ? null : _connect,
            isLoading: _loading,
          ),
        ],
      ),
    );
  }
}
