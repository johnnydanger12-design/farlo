import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../../core/constants/app_colors.dart';
import '../last_login_method.dart';
import '../providers/auth_provider.dart';

class SocialAuthButtons extends ConsumerStatefulWidget {
  const SocialAuthButtons({super.key, required this.onError, this.lastMethod});

  final void Function(String message) onError;

  // Highlights whichever button matches how this device last signed in, so a
  // returning user doesn't have to guess between Apple/Google/email. Null
  // (first-ever launch, or last method was email) shows no badge here.
  final LastLoginMethod? lastMethod;

  @override
  ConsumerState<SocialAuthButtons> createState() => _SocialAuthButtonsState();
}

class _SocialAuthButtonsState extends ConsumerState<SocialAuthButtons> {
  bool _loading = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await action();
    } catch (_) {
      // Provider already set AsyncError — caller reads it via authProvider.error.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;
    final error = ref.read(authProvider).error;
    if (error != null) widget.onError(_friendlyError(error));
  }

  String _friendlyError(Object error) {
    debugPrint('Social sign-in error: $error');
    final msg = error.toString().toLowerCase();
    if (msg.contains('network') || msg.contains('socket')) {
      return 'No internet connection. Please try again.';
    }
    if (msg.contains('timeout')) {
      return 'Request timed out. Check your connection and try again.';
    }
    return 'Sign-in failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _loading,
      child: Opacity(
        opacity: _loading ? 0.6 : 1.0,
        child: Column(
          children: [
            if (widget.lastMethod == LastLoginMethod.apple) const _LastUsedBadge(),
            SignInWithAppleButton(
              onPressed: () => _run(
                () => ref.read(authProvider.notifier).signInWithApple(),
              ),
              style: SignInWithAppleButtonStyle.black,
              borderRadius: BorderRadius.circular(12),
              height: 52,
            ),
            const SizedBox(height: 12),
            if (widget.lastMethod == LastLoginMethod.google) const _LastUsedBadge(),
            _GoogleButton(
              onPressed: () => _run(
                () => ref.read(authProvider.notifier).signInWithGoogle(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LastUsedBadge extends StatelessWidget {
  const _LastUsedBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Used last time',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(fontSize: 13, color: color),
          ),
        ),
        Expanded(child: Divider(color: color)),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: isDark ? const Color(0xFF2D2D2D) : Colors.white,
          foregroundColor: isDark ? Colors.white : const Color(0xFF1F1F1F),
          side: BorderSide(
            color: isDark ? const Color(0xFF5F6368) : const Color(0xFFDEDEDE),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        icon: const FaIcon(FontAwesomeIcons.google, size: 18, color: Color(0xFF4285F4)),
        label: const Text('Continue with Google'),
      ),
    );
  }
}
