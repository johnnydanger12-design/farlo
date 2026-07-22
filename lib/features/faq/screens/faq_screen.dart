import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/faq_item.dart';
import '../providers/faq_provider.dart';

class FaqScreen extends ConsumerWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItems = ref.watch(faqItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & FAQ', style: AppTextStyles.heading3),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: asyncItems.when(
        loading: () => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text('No FAQ content yet.', style: AppTextStyles.body.copyWith(color: AppColors.textHint)),
            );
          }
          // Items already arrive ordered by category_sort_order then sort_order.
          final categories = <String>[];
          final byCategory = <String, List<FaqItem>>{};
          for (final item in items) {
            final list = byCategory.putIfAbsent(item.category, () {
              categories.add(item.category);
              return [];
            });
            list.add(item);
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final questions = byCategory[category]!;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 4),
                      child: Text(
                        category,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    ...questions.map((q) => _FaqTile(item: q)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.item});
  final FaqItem item;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(item.question, style: AppTextStyles.bodySmall),
      childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      expandedAlignment: Alignment.centerLeft,
      children: [
        Text(
          item.answer,
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
