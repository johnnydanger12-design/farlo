import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../providers/pos_integration_provider.dart';

class ConnectCloverScreen extends ConsumerStatefulWidget {
  const ConnectCloverScreen({super.key});

  @override
  ConsumerState<ConnectCloverScreen> createState() => _ConnectCloverScreenState();
}

class _ConnectCloverScreenState extends ConsumerState<ConnectCloverScreen> {
  final _merchantIdCtrl = TextEditingController();
  final _apiTokenCtrl = TextEditingController();
  final _orderTypeIdCtrl = TextEditingController();
  String _environment = 'production';

  bool _showAdvanced = false;
  bool _testing = false;
  bool _saving = false;

  // Reset to false on any field edit — Save is only enabled right after a
  // fresh, successful Test Connection, never off a stale result.
  bool _tested = false;
  String? _testError;

  @override
  void initState() {
    super.initState();
    for (final ctrl in [_merchantIdCtrl, _apiTokenCtrl, _orderTypeIdCtrl]) {
      ctrl.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    _merchantIdCtrl.dispose();
    _apiTokenCtrl.dispose();
    _orderTypeIdCtrl.dispose();
    super.dispose();
  }

  // Always rebuilds (Test Connection's enabled state depends on live field
  // content) and additionally resets any previous test result so Save can
  // never trust a result that predates the field being edited.
  void _onFieldChanged() {
    setState(() {
      _tested = false;
      _testError = null;
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testError = null;
    });
    try {
      final result = await ref.read(posIntegrationRepositoryProvider).testCloverConnection(
            merchantId: _merchantIdCtrl.text.trim(),
            apiToken: _apiTokenCtrl.text.trim(),
            environment: _environment,
          );
      setState(() {
        _tested = result.ok;
        _testError = result.ok ? null : (result.message ?? 'Connection failed.');
      });
    } catch (e) {
      setState(() => _testError = sanitizeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(posIntegrationRepositoryProvider).connectClover(
            merchantId: _merchantIdCtrl.text.trim(),
            apiToken: _apiTokenCtrl.text.trim(),
            environment: _environment,
            orderTypeId: _orderTypeIdCtrl.text.trim(),
          );
      ref.invalidate(posIntegrationProvider);
      if (mounted) {
        context.showSuccess('Clover connected!', duration: const Duration(seconds: 2), backgroundColor: AppColors.openGreen);
        context.pop();
      }
    } catch (e) {
      if (mounted) context.showError('Could not connect: ${sanitizeErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Clover'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: 'Merchant ID',
              hint: 'From your Clover dashboard URL',
              controller: _merchantIdCtrl,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'API Token',
              hint: 'Generated with Orders, Print, Payments & Customers scopes',
              controller: _apiTokenCtrl,
              obscureText: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _environment,
              decoration: InputDecoration(
                labelText: 'Environment',
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
                if (val == null) return;
                setState(() {
                  _environment = val;
                  _tested = false;
                  _testError = null;
                });
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Text(_showAdvanced ? 'Hide Advanced' : 'Show Advanced'),
            ),
            if (_showAdvanced) ...[
              AppTextField(
                label: 'Order Type ID (optional)',
                hint: 'Leave blank unless Clover support told you to set this',
                controller: _orderTypeIdCtrl,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.md),
            if (_testError != null) ...[
              Text(_testError!, style: AppTextStyles.caption.copyWith(color: Colors.red.shade700)),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (_tested) ...[
              Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  const SizedBox(width: 6),
                  Text('Connection verified', style: AppTextStyles.caption.copyWith(color: Colors.green.shade700)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            OutlinedButton(
              onPressed: (_testing || _merchantIdCtrl.text.trim().isEmpty || _apiTokenCtrl.text.trim().isEmpty)
                  ? null
                  : _testConnection,
              child: _testing
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Test Connection'),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Save',
              onPressed: (_tested && !_saving) ? _save : null,
              isLoading: _saving,
            ),
          ],
        ),
      ),
    );
  }
}
