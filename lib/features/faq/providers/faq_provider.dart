import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/faq_item.dart';
import '../repositories/faq_repository.dart';

final faqRepositoryProvider = Provider<FaqRepository>((ref) {
  return FaqRepository(Supabase.instance.client);
});

final faqItemsProvider = FutureProvider<List<FaqItem>>((ref) {
  return ref.read(faqRepositoryProvider).fetchAll();
});
