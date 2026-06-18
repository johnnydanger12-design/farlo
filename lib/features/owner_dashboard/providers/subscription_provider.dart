import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/subscription.dart';
import '../repositories/subscription_repository.dart';
import '../../../services/subscription_service.dart';
import '../../../core/rc_config.dart';

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

  Future<void> purchase({bool annual = false}) async {
    final service = ref.read(subscriptionServiceProvider);
    // Don't replace state with AsyncLoading — let the widget manage its own
    // loading indicator. Only update state after a successful purchase so the
    // screen doesn't flash to an error view on any failure.
    await service.purchase(annual: annual);
    final user = ref.read(authProvider).asData?.value;
    if (user == null) return;
    final updated = await ref
        .read(subscriptionRepositoryProvider)
        .fetchForOwner(user.id);
    state = AsyncData(updated);
  }

  Future<void> restore() async {
    final service = ref.read(subscriptionServiceProvider);
    await service.restore();
    final user = ref.read(authProvider).asData?.value;
    if (user == null) return;
    final updated = await ref
        .read(subscriptionRepositoryProvider)
        .fetchForOwner(user.id);
    state = AsyncData(updated);
  }

  Future<void> refresh() async => ref.invalidateSelf();
}

final subscriptionProvider =
    AsyncNotifierProvider<SubscriptionNotifier, Subscription?>(
  SubscriptionNotifier.new,
);

typedef SubPrices = ({
  String? monthlyLabel,
  String? annualLabel,
  double? monthlyRaw,
  double? annualRaw,
});

/// Fetches localized price labels + raw values for both monthly and annual packages.
/// Either or both may be null if not configured in RC / App Store.
final subscriptionPricesProvider = FutureProvider<SubPrices>((ref) async {
  if (!rcConfigured) {
    return (monthlyLabel: null, annualLabel: null, monthlyRaw: null, annualRaw: null);
  }
  final offerings = await Purchases.getOfferings();
  final packages = offerings.current?.availablePackages ?? [];
  String? monthlyLabel, annualLabel;
  double? monthlyRaw, annualRaw;
  for (final p in packages) {
    if (p.packageType == PackageType.monthly) {
      monthlyLabel = p.storeProduct.priceString;
      monthlyRaw = p.storeProduct.price;
    } else if (p.packageType == PackageType.annual) {
      annualLabel = p.storeProduct.priceString;
      annualRaw = p.storeProduct.price;
    }
  }
  return (
    monthlyLabel: monthlyLabel,
    annualLabel: annualLabel,
    monthlyRaw: monthlyRaw,
    annualRaw: annualRaw,
  );
});
