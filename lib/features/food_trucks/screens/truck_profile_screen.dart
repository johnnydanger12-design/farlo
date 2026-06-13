import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/star_rating_widget.dart';
import '../../../core/widgets/error_view.dart';
import '../../auth/providers/auth_provider.dart';
import '../../map/models/food_truck.dart';
import '../../food_trucks/models/menu_item.dart';
import '../providers/food_truck_provider.dart';
import '../../favorites/providers/favorites_provider.dart';
import '../../reviews/models/review.dart';
import '../../reviews/providers/reviews_provider.dart';
import '../../reviews/widgets/review_card.dart';
import '../../bookings/widgets/book_truck_sheet.dart';
import '../../reviews/widgets/write_review_sheet.dart';

class TruckProfileScreen extends ConsumerWidget {
  const TruckProfileScreen({
    super.key,
    required this.truckId,
    this.scrollToReviews = false,
  });

  final String truckId;
  final bool scrollToReviews;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTruck = ref.watch(foodTruckProvider(truckId));

    return asyncTruck.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: ErrorView(message: e.toString(), onRetry: () => ref.invalidate(foodTruckProvider(truckId))),
      ),
      data: (truck) => _TruckProfileContent(truck: truck, scrollToReviews: scrollToReviews),
    );
  }
}

class _TruckProfileContent extends ConsumerStatefulWidget {
  const _TruckProfileContent({required this.truck, this.scrollToReviews = false});
  final FoodTruck truck;
  final bool scrollToReviews;

  @override
  ConsumerState<_TruckProfileContent> createState() => _TruckProfileContentState();
}

class _TruckProfileContentState extends ConsumerState<_TruckProfileContent> {
  final _pageController = PageController();
  final _reviewsKey = GlobalKey();
  int _currentPhoto = 0;
  int? _filterRating;

  @override
  void initState() {
    super.initState();
    if (widget.scrollToReviews) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToReviews());
    }
  }

  void _scrollToReviews() {
    final ctx = _reviewsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _openBookingSheet() async {
    final truck = widget.truck;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BookTruckSheet(truckId: truck.id, truckName: truck.name),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent! The owner will be in touch.')),
      );
    }
  }

  Future<void> _openReviewSheet(Review? existing) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => WriteReviewSheet(truckId: widget.truck.id, existing: existing),
    );
    if (result == true) {
      // Refresh the truck to get updated rating/count
      ref.invalidate(foodTruckProvider(widget.truck.id));
    }
  }

  Future<void> _deleteReview(String reviewId) async {
    await ref.read(reviewsRepositoryProvider).deleteReview(reviewId);
    ref.invalidate(truckReviewsProvider(widget.truck.id));
    ref.invalidate(myReviewProvider(widget.truck.id));
    ref.invalidate(foodTruckProvider(widget.truck.id));
  }

  @override
  Widget build(BuildContext context) {
    final truck = widget.truck;
    final hasPhotos = truck.photoUrls.isNotEmpty;
    final asyncReviews = ref.watch(truckReviewsProvider(truck.id));
    final asyncMyReview = ref.watch(myReviewProvider(truck.id));
    final user = ref.watch(authProvider).asData?.value;
    final isAuthenticated = user != null;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero header ─────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
            actions: isAuthenticated
                ? [
                    IconButton(
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          (ref.watch(favoritedTruckIdsProvider).asData?.value.contains(truck.id) ?? false)
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          key: ValueKey(ref.watch(favoritedTruckIdsProvider).asData?.value.contains(truck.id)),
                          color: Colors.white,
                        ),
                      ),
                      onPressed: () => ref.read(favoritedTruckIdsProvider.notifier).toggle(truck.id),
                    ),
                  ]
                : null,
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
              color: Theme.of(context).colorScheme.surface,
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
                            const SizedBox(height: 4),
                            _FollowerCount(truckId: truck.id),
                          ],
                        ),
                      ),
                      _OpenBadge(isOpen: truck.isOpen),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  GestureDetector(
                    onTap: _scrollToReviews,
                    child: Row(
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
                  ),
                  if (isAuthenticated) ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: () => _openBookingSheet(),
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: const Text('Request Private Event'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ],
                  if (truck.description != null && truck.description!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    const Divider(),
                    const SizedBox(height: AppSpacing.md),
                    Text(truck.description!, style: AppTextStyles.body),
                  ],
                ],
              ),
            ),
          ),

          const _SectionSpacer(),


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

          // ── Social media ─────────────────────────────────────────────────
          if (truck.socialInstagram != null ||
              truck.socialTiktok != null ||
              truck.socialFacebook != null ||
              truck.socialTwitter != null ||
              truck.socialYoutube != null ||
              truck.websiteUrl != null) ...[
            const _SectionSpacer(),
            SliverToBoxAdapter(
              child: _SocialSection(truck: truck),
            ),
          ],

          const _SectionSpacer(),

          // ── Reviews ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              key: _reviewsKey,
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Reviews', style: AppTextStyles.heading3),
                      asyncMyReview.when(
                        data: (myReview) => myReview == null
                            ? TextButton(
                                onPressed: isAuthenticated
                                    ? () => _openReviewSheet(null)
                                    : () => _showLoginPrompt(context),
                                child: Text(
                                  'Write a Review',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  asyncReviews.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Could not load reviews', style: AppTextStyles.bodySmall),
                    data: (reviews) {
                      if (reviews.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                          child: Center(
                            child: Text('No reviews yet — be the first!', style: AppTextStyles.bodySmall),
                          ),
                        );
                      }
                      final filtered = _filterRating == null
                          ? reviews
                          : reviews.where((r) => r.rating == _filterRating).toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ReviewFilter(
                            selected: _filterRating,
                            onSelected: (v) => setState(() => _filterRating = v),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                              child: Center(
                                child: Text('No ${_filterRating!}-star reviews yet', style: AppTextStyles.bodySmall),
                              ),
                            )
                          else
                            ...filtered.map((r) {
                              final isOwn = r.userId == user?.id;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                child: ReviewCard(
                                  review: r,
                                  isOwn: isOwn,
                                  onEdit: isOwn ? () => _openReviewSheet(r) : null,
                                  onDelete: isOwn ? () => _deleteReview(r.id) : null,
                                ),
                              );
                            }),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        ],
      ),
    );
  }

  void _showLoginPrompt(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign in required'),
        content: const Text('You need to be signed in to leave a review.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _SocialSection extends StatelessWidget {
  const _SocialSection({required this.truck});
  final FoodTruck truck;

  static const _platforms = [
    (field: 'instagram', icon: FontAwesomeIcons.instagram,  color: Color(0xFFE1306C)),
    (field: 'tiktok',    icon: FontAwesomeIcons.tiktok,     color: Color(0xFF010101)),
    (field: 'facebook',  icon: FontAwesomeIcons.facebook,   color: Color(0xFF1877F2)),
    (field: 'twitter',   icon: FontAwesomeIcons.xTwitter,   color: Color(0xFF000000)),
    (field: 'youtube',   icon: FontAwesomeIcons.youtube,    color: Color(0xFFFF0000)),
  ];

  String? _handleFor(String field) => switch (field) {
    'instagram' => truck.socialInstagram,
    'tiktok'    => truck.socialTiktok,
    'facebook'  => truck.socialFacebook,
    'twitter'   => truck.socialTwitter,
    'youtube'   => truck.socialYoutube,
    _           => null,
  };

  String _urlFor(String field, String handle) => switch (field) {
    'instagram' => 'https://instagram.com/$handle',
    'tiktok'    => 'https://tiktok.com/@$handle',
    'facebook'  => 'https://facebook.com/$handle',
    'twitter'   => 'https://x.com/$handle',
    'youtube'   => 'https://youtube.com/@$handle',
    _           => handle,
  };

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final platformButtons = _platforms
        .map((p) {
          final handle = _handleFor(p.field);
          if (handle == null) return null;
          final iconColor = (p.field == 'twitter' || p.field == 'tiktok') && isDark
              ? Colors.white
              : p.color;
          return _SocialButton(
            icon: p.icon,
            color: iconColor,
            onTap: () => _launch(_urlFor(p.field, handle)),
          );
        })
        .whereType<Widget>()
        .toList();

    if (truck.websiteUrl != null) {
      platformButtons.add(_SocialButton(
        icon: FontAwesomeIcons.globe,
        color: Theme.of(context).colorScheme.primary,
        onTap: () => _launch(truck.websiteUrl!),
      ));
    }

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Follow Us', style: AppTextStyles.heading3),
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: platformButtons),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.icon, required this.color, required this.onTap});
  final FaIconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: FaIcon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

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
    return Stack(
      children: [
        PageView.builder(
          controller: controller,
          itemCount: urls.length,
          onPageChanged: onPageChanged,
          itemBuilder: (_, i) => Image.network(
            urls[i],
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _LogoHero(logoUrl: null),
          ),
        ),
        if (urls.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(urls.length, (i) {
                final active = i == currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: active ? 1.0 : 0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
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

class _FollowerCount extends ConsumerWidget {
  const _FollowerCount({required this.truckId});
  final String truckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(truckFollowerCountProvider(truckId));
    return countAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (count) {
        final label = count == 1 ? '1 follower' : '$count followers';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border_rounded, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.caption),
          ],
        );
      },
    );
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
      color: Theme.of(context).colorScheme.surface,
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

class _MenuList extends StatelessWidget {
  const _MenuList({required this.items});
  final List<MenuItem> items;

  @override
  Widget build(BuildContext context) {
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

class _ReviewFilter extends StatelessWidget {
  const _ReviewFilter({required this.selected, required this.onSelected});

  final int? selected;
  final void Function(int?) onSelected;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            active: selected == null,
            onTap: () => onSelected(null),
            primary: primary,
          ),
          ...List.generate(5, (i) {
            final star = 5 - i;
            return _FilterChip(
              label: '$star ★',
              active: selected == star,
              onTap: () => onSelected(selected == star ? null : star),
              primary: primary,
            );
          }),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
    required this.primary,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? primary : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
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
