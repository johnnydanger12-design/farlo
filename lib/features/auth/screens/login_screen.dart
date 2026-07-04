import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../providers/auth_provider.dart';
import '../widgets/social_auth_buttons.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    await ref.read(authProvider.notifier).signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
    final error = ref.read(authProvider).error;
    TextInput.finishAutofillContext(shouldSave: error == null);
    if (mounted) {
      setState(() => _isLoading = false);
      if (error != null) _showError(_friendlyError(error));
    }
  }

  String _friendlyError(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('network') || msg.contains('socket')) {
      return 'No internet connection. Please try again.';
    }
    if (msg.contains('timeout')) {
      return 'Request timed out. Check your connection and try again.';
    }
    if (msg.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Please confirm your email before signing in.';
    }
    return 'Sign-in failed. Please try again.';
  }

  void _showError(String message) {
    context.showError(message, behavior: SnackBarBehavior.floating);
  }

  void _showForgotPasswordDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _ForgotPasswordDialog(
        initialEmail: _emailController.text.trim(),
        onSend: (email) => ref.read(authRepositoryProvider).resetPasswordForEmail(email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Image.asset(
                    'assets/images/Farlo Logo.png',
                    width: double.infinity,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text('Welcome', style: AppTextStyles.heading1),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Sign in to discover local businesses near you.',
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: AppSpacing.lg),
                SocialAuthButtons(onError: _showError),
                const SizedBox(height: AppSpacing.lg),
                const OrDivider(),
                const SizedBox(height: AppSpacing.lg),
                AutofillGroup(
                  onDisposeAction: AutofillContextAction.cancel,
                  child: Column(
                    children: [
                      AppTextField(
                        label: 'Email',
                        controller: _emailController,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.none,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Enter your email';
                          if (!v.contains('@')) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        label: 'Password',
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.none,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        autofillHints: const [AutofillHints.password],
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Enter your password';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _showForgotPasswordDialog(context),
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(fontSize: 13, color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Sign In',
                  onPressed: _submit,
                  isLoading: _isLoading,
                  backgroundColor: AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account? ", style: AppTextStyles.bodySmall),
                    Semantics(
                      button: true,
                      child: GestureDetector(
                        onTap: () => context.go('/register'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'Sign up',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Have a business? ', style: AppTextStyles.bodySmall),
                    Semantics(
                      button: true,
                      child: GestureDetector(
                        onTap: () => context.go('/register-owner'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'Get listed',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: Semantics(
                    button: true,
                    child: GestureDetector(
                      onTap: () => context.go('/map'),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                        child: Text(
                          'Browse as guest',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ForgotPasswordDialog extends ConsumerStatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail, required this.onSend});
  final String initialEmail;
  final Future<void> Function(String email) onSend;

  @override
  ConsumerState<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends ConsumerState<_ForgotPasswordDialog> {
  late final TextEditingController _ctrl;
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _ctrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await widget.onSend(email);
      if (mounted) setState(() { _loading = false; _sent = true; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Something went wrong. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    if (_sent) {
      return AlertDialog(
        backgroundColor: isLight ? Colors.white : null,
        title: const Text('Check your inbox', textAlign: TextAlign.center),
        content: Text(
          'A password reset link has been sent to ${_ctrl.text.trim()}.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: isLight ? Colors.white : null,
      title: const Text('Reset Password', textAlign: TextAlign.center),
      content: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter your email and we\'ll send you a reset link.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofocus: widget.initialEmail.isEmpty,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Email address'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ],
        ],
      ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send Link'),
        ),
      ],
    );
  }
}
