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

  Future<void> purchase() async {
    if (!rcConfigured) throw Exception('Subscription service is not available in this build.');
    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null || current.availablePackages.isEmpty) {
      throw Exception('No subscription offerings available. Please try again later.');
    }
    final package = current.availablePackages.first;
    await Purchases.purchase(PurchaseParams.package(package));
  }

  Future<void> restore() async {
    if (!rcConfigured) throw Exception('Subscription service is not available in this build.');
    await Purchases.restorePurchases();
  }
}

final subscriptionServiceProvider = Provider<SubscriptionService>((_) => SubscriptionService());
