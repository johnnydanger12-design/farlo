import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/faq_item.dart';

class FaqRepository {
  FaqRepository(this._supabase);
  final SupabaseClient _supabase;

  Future<List<FaqItem>> fetchAll() async {
    final rows = await _supabase
        .from('faq_items')
        .select()
        .order('category_sort_order', ascending: true)
        .order('sort_order', ascending: true);
    return (rows as List).map((r) => FaqItem.fromMap(r as Map<String, dynamic>)).toList();
  }
}
