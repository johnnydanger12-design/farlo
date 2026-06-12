import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/subscription.dart';
import '../repositories/subscription_repository.dart';
import '../../../services/subscription_service.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(ref.watch(supabaseClientProvider));
});

class SubscriptionNotifier extends AsyncNotifier<Subscription?> {
  @override
  Future<Subscription?> build() async {
    final user = ref.watch(authProvider).asData?.value;
    if (user == null || !user.isOwner) return null;
    return ref.read(subscriptionRepositoryProvider).fetchForOwner(user.id);
  }

  Future<void> purchase() async {
    final service = ref.read(subscriptionServiceProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await service.purchase();
      final user = ref.read(authProvider).asData?.value;
      if (user == null) return null;
      return ref.read(subscriptionRepositoryProvider).fetchForOwner(user.id);
    });
  }

  Future<void> restore() async {
    final service = ref.read(subscriptionServiceProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await service.restore();
      final user = ref.read(authProvider).asData?.value;
      if (user == null) return null;
      return ref.read(subscriptionRepositoryProvider).fetchForOwner(user.id);
    });
  }

  Future<void> refresh() async => ref.invalidateSelf();
}

final subscriptionProvider =
    AsyncNotifierProvider<SubscriptionNotifier, Subscription?>(
  SubscriptionNotifier.new,
);
