import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/faq_item.dart';
import '../providers/faq_provider.dart';

class FaqScreen extends ConsumerStatefulWidget {
  const FaqScreen({super.key});

  @override
  ConsumerState<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends ConsumerState<FaqScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

          final query = _query.trim().toLowerCase();
          final filtered = query.isEmpty
              ? items
              : items
                  .where((i) =>
                      i.question.toLowerCase().contains(query) || i.answer.toLowerCase().contains(query))
                  .toList();

          // Items already arrive ordered by category_sort_order then sort_order.
          final categories = <String>[];
          final byCategory = <String, List<FaqItem>>{};
          for (final item in filtered) {
            final list = byCategory.putIfAbsent(item.category, () {
              categories.add(item.category);
              return [];
            });
            list.add(item);
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search FAQ…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _query = '';
                            }),
                          ),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: AppSpacing.md),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: categories.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        children: [
                          const SizedBox(height: AppSpacing.xl),
                          Center(
                            child: Text(
                              "No results for \"${_query.trim()}\"",
                              style: AppTextStyles.body.copyWith(color: AppColors.textHint),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const _ContactSupportCard(),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                        // +1 for the Contact Support footer card at the very end.
                        itemCount: categories.length + 1,
                        itemBuilder: (context, index) {
                          if (index == categories.length) {
                            return const Padding(
                              padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                              child: _ContactSupportCard(),
                            );
                          }
                          final category = categories[index];
                          final questions = byCategory[category]!;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 4),
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
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Deliberately at the bottom of the FAQ list, not a separate Account →
// Support menu item — the FAQ should have a real chance to answer a
// question before someone escalates to email (Johnny's call, 2026-07-24).
class _ContactSupportCard extends StatelessWidget {
  const _ContactSupportCard();

  Future<void> _contactSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@farlo.app',
      query: 'subject=Farlo%20Support%20Request',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Still need help?', style: AppTextStyles.label),
                const SizedBox(height: 2),
                Text(
                  "If you didn't find your answer above, we're happy to help.",
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _contactSupport,
            icon: const Icon(Icons.support_agent_outlined, size: 18),
            label: const Text('Contact Support'),
          ),
        ],
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
