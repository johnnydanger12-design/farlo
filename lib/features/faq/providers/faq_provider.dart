import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/providers/auth_provider.dart';
import '../models/faq_item.dart';
import '../repositories/faq_repository.dart';

final faqRepositoryProvider = Provider<FaqRepository>((ref) {
  return FaqRepository(Supabase.instance.client);
});

// Filters to the signed-in user's own role — 'both' always shows. Falls back
// to consumer content if somehow reached signed-out, though in practice this
// screen is only reachable from the authenticated Account tab.
final faqItemsProvider = FutureProvider<List<FaqItem>>((ref) async {
  final isOwner = ref.watch(authProvider).asData?.value?.isOwner ?? false;
  final items = await ref.read(faqRepositoryProvider).fetchAll();
  return items
      .where((i) => i.audience == 'both' || i.audience == (isOwner ? 'owner' : 'consumer'))
      .toList();
});
