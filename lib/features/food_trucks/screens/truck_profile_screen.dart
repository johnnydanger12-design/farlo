import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/star_rating_widget.dart';
import '../../../core/widgets/error_view.dart';
import '../../map/models/food_truck.dart';
import '../../food_trucks/models/operating_hours.dart';
import '../../food_trucks/models/menu_item.dart';
import '../providers/food_truck_provider.dart';

class TruckProfileScreen extends ConsumerWidget {
  const TruckProfileScreen({super.key, required this.truckId});

  final String truckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTruck = ref.watch(foodTruckProvider(truckId));

    return asyncTruck.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: ErrorView(message: e.toString(), onRetry: () => ref.invalidate(foodTruckProvider(truckId))),
      ),
      data: (truck) => _TruckProfileContent(truck: truck),
    );
  }
}

class _TruckProfileContent extends StatefulWidget {
  const _TruckProfileContent({required this.truck});
  final FoodTruck truck;

  @override
  State<_TruckProfileContent> createState() => _TruckProfileContentState();
}

class _TruckProfileContentState extends State<_TruckProfileContent> {
  final _pageController = PageController();
  int _currentPhoto = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final truck = widget.truck;
    final hasPhotos = truck.photoUrls.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Hero header ─────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: hasPhotos
                  ? _PhotoCarousel(
                      urls: truck.photoUrls,
                      controller: _pageController,
                      currentIndex: _currentPhoto,
                      onPageChanged: (i) => setState(() => _currentPhoto = i),
                    )
                  : _LogoHero(logoUrl: truck.logoUrl),
            ),
          ),

          // ── Truck identity ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: AppColors.surface,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(truck.name, style: AppTextStyles.heading2),
                            const SizedBox(height: 4),
                            Text(truck.cuisineType, style: AppTextStyles.bodySmall),
                          ],
                        ),
                      ),
                      _OpenBadge(isOpen: truck.isOpen),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      StarRatingWidget(rating: truck.averageRating, size: 16, showValue: false),
                      const SizedBox(width: 6),
                      Text(
                        truck.reviewCount > 0
                            ? '${truck.averageRating.toStringAsFixed(1)} · ${truck.reviewCount} review${truck.reviewCount == 1 ? '' : 's'}'
                            : 'No reviews yet',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                  if (truck.description != null && truck.description!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    const Divider(color: AppColors.divider),
                    const SizedBox(height: AppSpacing.md),
                    Text(truck.description!, style: AppTextStyles.body),
                  ],
                ],
              ),
            ),
          ),

          const _SectionSpacer(),

          // ── Photo dots (if multiple photos) ─────────────────────────────
          if (hasPhotos && truck.photoUrls.length > 1)
            SliverToBoxAdapter(
              child: Container(
                color: AppColors.surface,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(truck.photoUrls.length, (i) {
                    final active = i == _currentPhoto;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active ? Theme.of(context).colorScheme.primary : AppColors.divider,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
            ),

          if (hasPhotos && truck.photoUrls.length > 1) const _SectionSpacer(),

          // ── Operating hours ──────────────────────────────────────────────
          if (truck.operatingHours.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _Section(
                title: 'Hours',
                child: _HoursTable(hours: truck.operatingHours),
              ),
            ),
            const _SectionSpacer(),
          ],

          // ── Menu ─────────────────────────────────────────────────────────
          if (truck.menuItems.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _Section(
                title: 'Menu',
                child: _MenuList(items: truck.menuItems),
              ),
            ),
            const _SectionSpacer(),
          ],

          if (truck.menuItems.isEmpty && truck.menuPdfUrl == null && truck.menuImageUrl == null)
            SliverToBoxAdapter(
              child: _Section(
                title: 'Menu',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(
                    child: Text('Menu not available yet', style: AppTextStyles.bodySmall),
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _PhotoCarousel extends StatelessWidget {
  const _PhotoCarousel({
    required this.urls,
    required this.controller,
    required this.currentIndex,
    required this.onPageChanged,
  });

  final List<String> urls;
  final PageController controller;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      itemCount: urls.length,
      onPageChanged: onPageChanged,
      itemBuilder: (_, i) => Image.network(
        urls[i],
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _LogoHero(logoUrl: null),
      ),
    );
  }
}

class _LogoHero extends StatelessWidget {
  const _LogoHero({required this.logoUrl});
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.secondary,
      child: Center(
        child: logoUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  logoUrl!,
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _TruckIconPlaceholder(),
                ),
              )
            : const _TruckIconPlaceholder(),
      ),
    );
  }
}

class _TruckIconPlaceholder extends StatelessWidget {
  const _TruckIconPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.lunch_dining, color: Colors.white54, size: 72);
  }
}

class _OpenBadge extends StatelessWidget {
  const _OpenBadge({required this.isOpen});
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? AppColors.openGreen : AppColors.textHint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            isOpen ? 'Open' : 'Closed',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.heading3),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _SectionSpacer extends StatelessWidget {
  const _SectionSpacer();

  @override
  Widget build(BuildContext context) {
    return const SliverToBoxAdapter(child: SizedBox(height: 8));
  }
}

class _HoursTable extends StatelessWidget {
  const _HoursTable({required this.hours});
  final List<OperatingHours> hours;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday % 7; // weekday: Mon=1..Sun=7 → 0=Sun..6=Sat

    return Column(
      children: hours.map((h) {
        final isToday = h.dayOfWeek == today;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  h.dayName,
                  style: AppTextStyles.label.copyWith(
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    color: isToday ? Theme.of(context).colorScheme.primary : AppColors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  h.hoursDisplay,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: h.isClosed
                        ? AppColors.textHint
                        : (isToday ? Theme.of(context).colorScheme.primary : AppColors.textSecondary),
                    fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _MenuList extends StatelessWidget {
  const _MenuList({required this.items});
  final List<MenuItem> items;

  @override
  Widget build(BuildContext context) {
    // Group by category
    final categories = <String, List<MenuItem>>{};
    for (final item in items.where((i) => i.isAvailable)) {
      categories.putIfAbsent(item.category, () => []).add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: categories.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                entry.key,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            ...entry.value.map((item) => _MenuItemRow(item: item)),
            const SizedBox(height: AppSpacing.md),
          ],
        );
      }).toList(),
    );
  }
}

class _MenuItemRow extends StatelessWidget {
  const _MenuItemRow({required this.item});
  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                item.imageUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 56),
              ),
            ),
          if (item.imageUrl != null) const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AppTextStyles.label),
                if (item.description != null && item.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.description!,
                      style: AppTextStyles.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(item.priceDisplay, style: AppTextStyles.label),
        ],
      ),
    );
  }
}
