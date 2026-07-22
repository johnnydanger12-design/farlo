// Reached when square-oauth-callback left the connection pending because the
// merchant has more than one Square location. UNVERIFIED end-to-end — no real
// Square Application exists yet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../providers/pos_integration_provider.dart';

class SquareLocationPickerScreen extends ConsumerStatefulWidget {
  const SquareLocationPickerScreen({super.key});

  @override
  ConsumerState<SquareLocationPickerScreen> createState() => _SquareLocationPickerScreenState();
}

class _SquareLocationPickerScreenState extends ConsumerState<SquareLocationPickerScreen> {
  late Future<List<({String id, String name})>> _locationsFuture;
  String? _selectingId;

  @override
  void initState() {
    super.initState();
    _locationsFuture = ref.read(posIntegrationRepositoryProvider).fetchSquareLocations();
  }

  Future<void> _select(String locationId) async {
    setState(() => _selectingId = locationId);
    try {
      await ref.read(posIntegrationRepositoryProvider).selectSquareLocation(locationId);
      ref.invalidate(posIntegrationProvider);
      if (mounted) {
        context.showSuccess('Square connected!');
        context.pop();
        context.pop();
      }
    } catch (e) {
      if (mounted) context.showError(sanitizeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _selectingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Location'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
      ),
      body: FutureBuilder<List<({String id, String name})>>(
        future: _locationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${sanitizeErrorMessage(snapshot.error!)}'));
          }
          final locations = snapshot.data ?? [];
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: locations.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final loc = locations[i];
              return ListTile(
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text(loc.name),
                trailing: _selectingId == loc.id
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right),
                onTap: _selectingId != null ? null : () => _select(loc.id),
              );
            },
          );
        },
      ),
    );
  }
}
