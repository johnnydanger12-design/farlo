import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../bookings/widgets/places_autocomplete_field.dart';
import '../providers/auth_provider.dart';
import '../widgets/business_type_picker.dart';
import '../widgets/social_auth_buttons.dart';

class RegisterOwnerScreen extends ConsumerStatefulWidget {
  const RegisterOwnerScreen({super.key});

  @override
  ConsumerState<RegisterOwnerScreen> createState() => _RegisterOwnerScreenState();
}

class _RegisterOwnerScreenState extends ConsumerState<RegisterOwnerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _addressController = TextEditingController();
  String _businessType = 'mobile';
  double? _lat;
  double? _lng;
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _businessNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String? get _businessName {
    final v = _businessNameController.text.trim();
    return v.isEmpty ? null : v;
  }

  bool get _isFixed => _businessType == 'fixed';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isFixed && _lat == null) {
      _showError('Select your business address from the suggestions.');
      return;
    }
    setState(() => _isLoading = true);
    await ref.read(authProvider.notifier).signUpOwner(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
          truckName: _businessNameController.text.trim(),
          businessType: _businessType,
          address: _isFixed ? _addressController.text.trim() : null,
          lat: _isFixed ? _lat : null,
          lng: _isFixed ? _lng : null,
        );
    final error = ref.read(authProvider).error;
    TextInput.finishAutofillContext(shouldSave: error == null);
    if (mounted) {
      setState(() => _isLoading = false);
      if (error != null) _showError(error.toString());
    }
  }

  Future<void> _socialSignUp(Future<void> Function() action) async {
    if (_businessName == null) {
      _showError('Enter your business name first.');
      return;
    }
    if (_isFixed && _lat == null) {
      _showError('Select your business address from the suggestions.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await action();
    } catch (_) {
      // Provider sets AsyncError; read below.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (!mounted) return;
    final error = ref.read(authProvider).error;
    if (error != null) _showError(_friendlyError(error));
  }

  String _friendlyError(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('network') || msg.contains('socket')) {
      return 'No internet connection. Please try again.';
    }
    if (msg.contains('timeout')) {
      return 'Request timed out. Check your connection and try again.';
    }
    return 'Sign-up failed. Please try again.';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _isLoading,
        child: Opacity(
          opacity: _isLoading ? 0.6 : 1.0,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('List your business', style: AppTextStyles.heading1),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Create your owner account and start advertising your location.',
                      style: AppTextStyles.body,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              '14-day free trial included. No credit card required to start.',
                              style: TextStyle(fontSize: 13, color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // ── Business type picker ─────────────────────────────────
                    const Text('Business type', style: AppTextStyles.label),
                    const SizedBox(height: AppSpacing.sm),
                    BusinessTypePicker(
                      selected: _businessType,
                      onChanged: (t) => setState(() {
                        _businessType = t;
                        _lat = null;
                        _lng = null;
                        _addressController.clear();
                      }),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Business name ────────────────────────────────────────
                    const Text('Your business', style: AppTextStyles.label),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(
                      label: 'Business name',
                      controller: _businessNameController,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your business name'
                          : null,
                    ),
                    if (_isFixed) ...[
                      const SizedBox(height: AppSpacing.md),
                      PlacesAutocompleteField(
                        controller: _addressController,
                        label: '* Business address',
                        onCoordinatesSelected: (lat, lng) => setState(() { _lat = lat; _lng = lng; }),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your business address' : null,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),

                    // ── Social sign-up ───────────────────────────────────────
                    SignInWithAppleButton(
                      onPressed: () => _socialSignUp(
                        () => ref.read(authProvider.notifier).signUpOwnerWithApple(
                          _businessName!,
                          businessType: _businessType,
                          address: _isFixed ? _addressController.text.trim() : null,
                          lat: _isFixed ? _lat : null,
                          lng: _isFixed ? _lng : null,
                        ),
                      ),
                      style: SignInWithAppleButtonStyle.black,
                      borderRadius: BorderRadius.circular(12),
                      height: 52,
                    ),
                    const SizedBox(height: 12),
                    _GoogleButton(
                      onPressed: () => _socialSignUp(
                        () => ref.read(authProvider.notifier).signUpOwnerWithGoogle(
                          _businessName!,
                          businessType: _businessType,
                          address: _isFixed ? _addressController.text.trim() : null,
                          lat: _isFixed ? _lat : null,
                          lng: _isFixed ? _lng : null,
                        ),
                      ),
                      isDark: isDark,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const OrDivider(),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Email / password form ────────────────────────────────
                    const Text('Your info', style: AppTextStyles.label),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(
                      label: 'Your name',
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
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
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            autofillHints: const [AutofillHints.newPassword],
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            validator: (v) {
                              if (v == null || v.length < 8) return 'Password must be at least 8 characters';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      label: 'Create Owner Account',
                      onPressed: _submit,
                      isLoading: _isLoading,
                      backgroundColor: AppColors.primary,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Already have an account? ', style: AppTextStyles.bodySmall),
                        GestureDetector(
                          onTap: () => context.go('/login'),
                          child: const Text(
                            'Sign in',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed, required this.isDark});
  final VoidCallback onPressed;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
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

