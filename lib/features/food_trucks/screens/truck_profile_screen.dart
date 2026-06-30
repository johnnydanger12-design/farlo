import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/star_rating_widget.dart';
import '../../../core/widgets/error_view.dart';
import '../../auth/providers/auth_provider.dart';
import '../../map/models/food_truck.dart';
import '../../food_trucks/models/menu_item.dart';
import '../../food_trucks/models/operating_hours.dart';
import '../providers/food_truck_provider.dart';
import '../../favorites/providers/favorites_provider.dart';
import '../providers/announcement_prefs_provider.dart';
import '../../reviews/models/review.dart';
import '../../reviews/providers/reviews_provider.dart';
import '../../reviews/widgets/review_card.dart';
import '../../bookings/widgets/book_truck_sheet.dart';
import '../../orders/models/order_item.dart';
import '../../orders/providers/orders_provider.dart';
import '../../orders/widgets/order_cart_sheet.dart';
import '../../reviews/widgets/write_review_sheet.dart';
import '../../../core/widgets/sign_in_prompt_sheet.dart';

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
  RealtimeChannel? _truckChannel;
  RealtimeChannel? _menuChannel;
  late final CartNotifier _cartNotifier;

  @override
  void initState() {
    super.initState();
    _cartNotifier = ref.read(cartProvider.notifier);
    if (widget.scrollToReviews) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToReviews());
    }
    _truckChannel = Supabase.instance.client
        .channel('truck-profile-${widget.truck.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'food_trucks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.truck.id,
          ),
          callback: (_) { if (mounted) ref.invalidate(foodTruckProvider(widget.truck.id)); },
        )
        .subscribe();
    // Realtime: refresh when the owner changes menu item availability.
    _menuChannel = Supabase.instance.client
        .channel('truck-menu-${widget.truck.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'menu_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: widget.truck.id,
          ),
          callback: (_) { if (mounted) ref.invalidate(foodTruckProvider(widget.truck.id)); },
        )
        .subscribe();
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
    if (_truckChannel != null) {
      Supabase.instance.client.removeChannel(_truckChannel!);
    }
    if (_menuChannel != null) {
      Supabase.instance.client.removeChannel(_menuChannel!);
    }
    _pageController.dispose();
    Future.microtask(() => _cartNotifier.clear());
    super.dispose();
  }

  Future<void> _openBookingSheet() async {
    final truck = widget.truck;

    // Check that the truck owner has an active subscription before allowing
    // a booking request — bookings are a subscription-gated feature.
    final hasSubscription = await Supabase.instance.client
        .rpc('owner_has_active_subscription', params: {'p_owner_id': truck.ownerId});

    if (!mounted) return;

    if (hasSubscription != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This business isn\'t currently accepting booking requests.'),
        ),
      );
      return;
    }

    final topPadding = MediaQuery.of(context).viewPadding.top;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BookTruckSheet(truckId: truck.id, truckName: truck.name, topPadding: topPadding),
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
      builder: (_) => WriteReviewSheet(truckId: widget.truck.id, truckOwnerId: widget.truck.ownerId, existing: existing),
    );
    if (result == true) {
      ref.invalidate(truckReviewsProvider(widget.truck.id));
      ref.invalidate(myReviewProvider(widget.truck.id));
      ref.invalidate(foodTruckProvider(widget.truck.id));
    }
  }

  Future<void> _deleteReview(String reviewId) async {
    await ref.read(reviewsRepositoryProvider).deleteReview(reviewId);
    ref.invalidate(truckReviewsProvider(widget.truck.id));
    ref.invalidate(myReviewProvider(widget.truck.id));
    ref.invalidate(foodTruckProvider(widget.truck.id));
  }

  Future<void> _replyToReview(Review review, {String? existing}) async {
    final response = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OwnerReplySheet(existingResponse: existing),
    );
    if (response == null || !mounted) return;
    try {
      await ref.read(reviewsRepositoryProvider).respondToReview(review.id, response);
    } finally {
      ref.invalidate(truckReviewsProvider(widget.truck.id));
      ref.invalidate(myReviewProvider(widget.truck.id));
      ref.invalidate(foodTruckProvider(widget.truck.id));
    }
  }

  Future<void> _deleteOwnerResponse(Review review) async {
    try {
      await ref.read(reviewsRepositoryProvider).deleteOwnerResponse(review.id);
    } finally {
      ref.invalidate(truckReviewsProvider(widget.truck.id));
      ref.invalidate(myReviewProvider(widget.truck.id));
      ref.invalidate(foodTruckProvider(widget.truck.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final truck = widget.truck;
    final hasPhotos = truck.photoUrls.isNotEmpty;
    final asyncReviews = ref.watch(truckReviewsProvider(truck.id));
    final asyncMyReview = ref.watch(myReviewProvider(truck.id));
    final user = ref.watch(authProvider).asData?.value;
    final isAuthenticated = user != null;
    final isOwnerOfTruck = user?.id == truck.ownerId;

    final canOrder = truck.isOpen && truck.ordersEnabled && truck.ordersAccepting;

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
        slivers: [
          // ── Hero header ─────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
            actions: isAuthenticated
                ? [
                    // Bell — only shown when following this truck
                    if (ref.watch(favoritedTruckIdsProvider).asData?.value.contains(truck.id) ?? false)
                      _AnnouncementBellButton(truckId: truck.id),
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

          // ── Hours ────────────────────────────────────────────────────────
          if (truck.operatingHours.isNotEmpty) ...[
            const _SectionSpacer(),
            SliverToBoxAdapter(
              child: _Section(
                title: 'Hours',
                child: _HoursTable(hours: truck.operatingHours),
              ),
            ),
          ],

          const _SectionSpacer(),

          // ── Order Now ────────────────────────────────────────────────────
          // ── Menu ─────────────────────────────────────────────────────────
          if (truck.menuItems.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _Section(
                title: 'Menu',
                child: _MenuGrid(items: truck.menuItems, canOrder: canOrder),
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
                        data: (myReview) => myReview == null && !isOwnerOfTruck
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
                                  isOwnerOfTruck: isOwnerOfTruck,
                                  onEdit: isOwn ? () => _openReviewSheet(r) : null,
                                  onDelete: isOwn ? () => _deleteReview(r.id) : null,
                                  onReply: isOwnerOfTruck ? () => _replyToReview(r) : null,
                                  onEditReply: isOwnerOfTruck ? () => _replyToReview(r, existing: r.ownerResponse) : null,
                                  onDeleteReply: isOwnerOfTruck ? () => _deleteOwnerResponse(r) : null,
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

          if (canOrder) const SliverToBoxAdapter(child: SizedBox(height: 88)),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        ],
          ),
          if (canOrder)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _FloatingCartBar(truck: truck),
            ),
        ],
      ),
    );
  }

  void _showLoginPrompt(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const SignInPromptSheet(),
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
    return const Icon(Icons.storefront_outlined, color: Colors.white54, size: 72);
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

class _HoursTable extends StatelessWidget {
  const _HoursTable({required this.hours});
  final List<OperatingHours> hours;

  @override
  Widget build(BuildContext context) {
    final todayIndex = DateTime.now().weekday % 7; // weekday: Mon=1…Sun=7 → Sun=0
    return Column(
      children: hours.map((h) {
        final isToday = h.dayOfWeek == todayIndex;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  h.dayName,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    color: isToday ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              ),
              Text(
                h.hoursDisplay,
                style: AppTextStyles.bodySmall.copyWith(
                  color: h.isClosed ? AppColors.textHint : null,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Today',
                    style: AppTextStyles.caption.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
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

// ─── Menu grid ────────────────────────────────────────────────────────────────

class _MenuGrid extends StatefulWidget {
  const _MenuGrid({required this.items, required this.canOrder});
  final List<MenuItem> items;
  final bool canOrder;

  @override
  State<_MenuGrid> createState() => _MenuGridState();
}

class _MenuGridState extends State<_MenuGrid> {
  late Map<String, bool> _expanded;

  Map<String, List<MenuItem>> _buildCategories() {
    final map = <String, List<MenuItem>>{};
    for (final item in widget.items.where((i) => i.isAvailable)) {
      map.putIfAbsent(item.category, () => []).add(item);
    }
    return map;
  }

  @override
  void initState() {
    super.initState();
    _expanded = {for (final k in _buildCategories().keys) k: false};
  }

  @override
  Widget build(BuildContext context) {
    final categories = _buildCategories();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: categories.entries.map((entry) {
        final isExpanded = _expanded[entry.key] ?? true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CategoryHeader(
              name: entry.key,
              itemCount: entry.value.length,
              isExpanded: isExpanded,
              onTap: () => setState(() => _expanded[entry.key] = !isExpanded),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: isExpanded
                  ? Column(
                      children: [
                        const SizedBox(height: AppSpacing.sm),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: AppSpacing.sm,
                            mainAxisSpacing: AppSpacing.sm,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: entry.value.length,
                          itemBuilder: (_, i) =>
                              _MenuItemCard(item: entry.value[i], canOrder: widget.canOrder),
                        ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        );
      }).toList(),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.name,
    required this.itemCount,
    required this.isExpanded,
    required this.onTap,
  });
  final String name;
  final int itemCount;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(name, style: AppTextStyles.label.copyWith(color: primary)),
            ),
            if (!isExpanded)
              Text('$itemCount item${itemCount == 1 ? '' : 's'}',
                  style: AppTextStyles.caption.copyWith(color: primary)),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: isExpanded ? 0 : -0.5,
              duration: const Duration(milliseconds: 220),
              child: Icon(Icons.keyboard_arrow_up, color: primary, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItemCard extends ConsumerWidget {
  const _MenuItemCard({required this.item, required this.canOrder});
  final MenuItem item;
  final bool canOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qty = canOrder ? (ref.watch(cartProvider)[item.id]?.quantity ?? 0) : 0;

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ItemDetailSheet(item: item, canOrder: canOrder),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: item.imageUrl != null
                    ? Image.network(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, _, _) => _NoPhotoPlaceholder(),
                      )
                    : _NoPhotoPlaceholder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item.priceDisplay,
                          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700)),
                      if (canOrder)
                        _AddButton(item: item, qty: qty),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPhotoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
      child: const Center(child: Icon(Icons.restaurant_menu_outlined, color: AppColors.textHint, size: 32)),
    );
  }
}

bool _tryAddToCart(BuildContext context, WidgetRef ref, CartItem item) {
  if (ref.read(authProvider).asData?.value == null) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const SignInPromptSheet(),
    );
    return false;
  }
  ref.read(cartProvider.notifier).add(item);
  return true;
}

class _AddButton extends ConsumerWidget {
  const _AddButton({required this.item, required this.qty});
  final MenuItem item;
  final int qty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: () => _tryAddToCart(context, ref, CartItem(
        menuItemId: item.id,
        name: item.name,
        price: item.price,
        quantity: 1,
      )),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: qty == 0
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: qty == 0
            ? const Icon(Icons.add, size: 14, color: Colors.white)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 11, color: Colors.white),
                  const SizedBox(width: 3),
                  Text('$qty',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }
}

class _ItemDetailSheet extends StatelessWidget {
  const _ItemDetailSheet({required this.item, required this.canOrder});
  final MenuItem item;
  final bool canOrder;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imageUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Image.network(
                item.imageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(item.name, style: AppTextStyles.heading3)),
                    const SizedBox(width: AppSpacing.sm),
                    Text(item.priceDisplay,
                        style: AppTextStyles.heading3.copyWith(
                            color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
                if (item.description != null && item.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(item.description!, style: AppTextStyles.body),
                ],
                if (canOrder) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Consumer(
                    builder: (context, ref, _) {
                      final qty = ref.watch(cartProvider)[item.id]?.quantity ?? 0;
                      return FilledButton.icon(
                        onPressed: () {
                          final added = _tryAddToCart(context, ref, CartItem(
                            menuItemId: item.id,
                            name: item.name,
                            price: item.price,
                            quantity: 1,
                          ));
                          if (added) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                        label: Text(qty == 0 ? 'Add to Bag' : 'Add One More'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      );
                    },
                  ),
                ],
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom + AppSpacing.sm),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingCartBar extends ConsumerWidget {
  const _FloatingCartBar({required this.truck});
  final FoodTruck truck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(cartProvider.notifier);
    final total = notifier.total;
    final count = notifier.totalQuantity;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
        child: FilledButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => OrderCartSheet(truck: truck),
            );
          },
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('$count',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const Text('View Bag',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
              Text('\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
        ),
      ),
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

class _OwnerReplySheet extends StatefulWidget {
  const _OwnerReplySheet({this.existingResponse});
  final String? existingResponse;

  @override
  State<_OwnerReplySheet> createState() => _OwnerReplySheetState();
}

class _OwnerReplySheetState extends State<_OwnerReplySheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.existingResponse);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final canSubmit = _ctrl.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg + bottomPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            widget.existingResponse == null ? 'Reply to Review' : 'Edit Reply',
            style: AppTextStyles.heading3,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Thank the customer or address their feedback…',
              alignLabelWithHint: true,
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canSubmit ? () => Navigator.pop(context, _ctrl.text.trim()) : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
              ),
              child: Text(widget.existingResponse == null ? 'Post Reply' : 'Save Reply'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Announcement bell toggle ───────────────────────────────────────────────────

class _AnnouncementBellButton extends ConsumerWidget {
  const _AnnouncementBellButton({required this.truckId});
  final String truckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(announcementPrefProvider(truckId)).asData?.value ?? true;
    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          enabled ? Icons.notifications_rounded : Icons.notifications_off_outlined,
          key: ValueKey(enabled),
          color: Colors.white,
        ),
      ),
      tooltip: enabled ? 'Mute announcements' : 'Unmute announcements',
      onPressed: () async {
        await ref.read(announcementPrefProvider(truckId).notifier).toggle();
        if (!context.mounted) return;
        final nowEnabled = ref.read(announcementPrefProvider(truckId)).asData?.value ?? true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nowEnabled
                ? 'Announcements turned on'
                : 'Announcements muted for this business'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}

