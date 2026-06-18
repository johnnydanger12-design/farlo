import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../core/rc_config.dart';

const _entitlementId = 'premium';

class SubscriptionService {
  Future<bool> isEntitled() async {
    if (!rcConfigured) return false;
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.containsKey(_entitlementId);
  }

  Future<void> purchase({bool annual = false}) async {
    if (!rcConfigured) throw Exception('Subscription service is not available in this build.');
    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null || current.availablePackages.isEmpty) {
      throw Exception('No subscription offerings available. Please try again later.');
    }
    final targetType = annual ? PackageType.annual : PackageType.monthly;
    final package = current.availablePackages.firstWhere(
      (p) => p.packageType == targetType,
      orElse: () => current.availablePackages.first,
    );
    await Purchases.purchase(PurchaseParams.package(package));
  }

  Future<void> restore() async {
    if (!rcConfigured) throw Exception('Subscription service is not available in this build.');
    final info = await Purchases.restorePurchases();
    if (!info.entitlements.active.containsKey(_entitlementId)) {
      throw Exception('No active purchases found to restore.');
    }
  }
}

final subscriptionServiceProvider = Provider<SubscriptionService>((_) => SubscriptionService());
