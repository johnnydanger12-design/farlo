import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Bump this alongside pubspec.yaml's build number on every release -- it's
// what gets compared against app_min_build_numbers at cold start. There's no
// runtime way to read this back out of the binary without adding a native
// plugin (package_info_plus), so it's a second manual step for now, same as
// the version/build-number bump this project already does by hand every
// submission (see HANDOFF.md's release checklist).
const kAppBuildNumber = 17;

const _iosAppStoreUrl = 'https://apps.apple.com/us/app/farlo/id6781018329';
const _androidPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.farlo.app';

// Fails open on any error (no network, table not reachable, timeout) --
// an availability bug in this check would be worse than just not enforcing
// a force-update this one time. 5s cap so a slow/absent network never stalls
// app launch waiting on this. Null minBuildNumber means "couldn't check,
// don't block."
Future<({int? minBuildNumber, String? updateMessage})> fetchVersionRequirement() async {
  try {
    final platform = Platform.isIOS ? 'ios' : 'android';
    final row = await Supabase.instance.client
        .from('app_min_build_numbers')
        .select('min_build_number, update_message')
        .eq('platform', platform)
        .maybeSingle()
        .timeout(const Duration(seconds: 5));
    return (
      minBuildNumber: row?['min_build_number'] as int?,
      updateMessage: row?['update_message'] as String?,
    );
  } catch (_) {
    return (minBuildNumber: null, updateMessage: null);
  }
}

// Standalone MaterialApp (not the real router/AppShell) -- shown instead of
// the app entirely when the running build is below the enforced minimum.
// Deliberately has no back button / dismiss path.
class UpdateRequiredApp extends StatelessWidget {
  const UpdateRequiredApp({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update, size: 64),
                  const SizedBox(height: 24),
                  Text(
                    'Update Required',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message ??
                        'A new version of Farlo is required to continue. Please update from the App Store to keep using the app.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      final url = Platform.isIOS ? _iosAppStoreUrl : _androidPlayStoreUrl;
                      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    },
                    child: const Text('Update Now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
