import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/star_rating_widget.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/snackbar_extensions.dart';
import '../../../core/widgets/tab_aware_bottom_sheet.dart';
import '../../auth/providers/auth_provider.dart';
import '../../map/models/food_truck.dart';
import '../../favorites/providers/favorites_provider.dart';
import '../providers/food_truck_provider.dart';
import '../../reviews/models/review.dart';
import '../../reviews/providers/reviews_provider.dart';
import '../../reviews/widgets/review_card.dart';
import '../../bookings/widgets/book_truck_sheet.dart';
import '../../employees/models/weekly_special.dart';
import '../../employees/providers/weekly_specials_provider.dart';
import '../../orders/providers/orders_provider.dart';
import '../../reviews/widgets/write_review_sheet.dart';
import '../../../core/widgets/sign_in_prompt_sheet.dart';
import '../widgets/truck_display_widgets.dart';
import '../widgets/truck_menu_widgets.dart';
import '../widgets/truck_review_widgets.dart';
import '../widgets/truck_social_widgets.dart';

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
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(foodTruckProvider(truckId)),
        ),
      ),
      data: (truck) =>
          _TruckProfileContent(truck: truck, scrollToReviews: scrollToReviews),
    );
  }
}

class _TruckProfileContent extends ConsumerStatefulWidget {
  const _TruckProfileContent({
    required this.truck,
    this.scrollToReviews = false,
  });
  final FoodTruck truck;
  final bool scrollToReviews;

  @override
  ConsumerState<_TruckProfileContent> createState() =>
      _TruckProfileContentState();
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
          callback: (_) {
            if (mounted) ref.invalidate(foodTruckProvider(widget.truck.id));
          },
        )
        .subscribe();
    // Realtime: refresh when the owner changes menu item availability/order,
    // or reorders categories.
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
          callback: (_) {
            if (mounted) ref.invalidate(foodTruckProvider(widget.truck.id));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'menu_categories',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'truck_id',
            value: widget.truck.id,
          ),
          callback: (_) {
            if (mounted) ref.invalidate(foodTruckProvider(widget.truck.id));
          },
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
    final hasSubscription = await Supabase.instance.client.rpc(
      'owner_has_active_subscription',
      params: {'p_owner_id': truck.ownerId},
    );

    if (!mounted) return;

    if (hasSubscription != true) {
      context.showInfo(
        'This business isn\'t currently accepting booking requests.',
      );
      return;
    }

    final topPadding = MediaQuery.of(context).viewPadding.top;
    final result = await showTabAwareModalBottomSheet<bool>(
      context: context,
      tabIndex: 0,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BookTruckSheet(
        truckId: truck.id,
        truckName: truck.name,
        topPadding: topPadding,
      ),
    );
    if (result == true && mounted) {
      context.showSuccess('Request sent! The owner will be in touch.');
    }
  }

  Future<void> _openReviewSheet(Review? existing) async {
    final result = await showTabAwareModalBottomSheet<bool>(
      context: context,
      tabIndex: 0,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => WriteReviewSheet(
        truckId: widget.truck.id,
        truckOwnerId: widget.truck.ownerId,
        existing: existing,
      ),
    );
    if (result == true) {
      ref.invalidate(truckReviewsBundleProvider(widget.truck.id));
      ref.invalidate(foodTruckProvider(widget.truck.id));
    }
  }

  Future<void> _deleteReview(String reviewId) async {
    await ref.read(reviewsRepositoryProvider).deleteReview(reviewId);
    ref.invalidate(truckReviewsBundleProvider(widget.truck.id));
    ref.invalidate(foodTruckProvider(widget.truck.id));
  }

  Future<void> _replyToReview(Review review, {String? existing}) async {
    final response = await showTabAwareModalBottomSheet<String>(
      context: context,
      tabIndex: 0,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OwnerReplySheet(existingResponse: existing),
    );
    if (response == null || !mounted) return;
    try {
      await ref
          .read(reviewsRepositoryProvider)
          .respondToReview(review.id, response);
    } finally {
      ref.invalidate(truckReviewsBundleProvider(widget.truck.id));
      ref.invalidate(foodTruckProvider(widget.truck.id));
    }
  }

  Future<void> _deleteOwnerResponse(Review review) async {
    try {
      await ref.read(reviewsRepositoryProvider).deleteOwnerResponse(review.id);
    } finally {
      ref.invalidate(truckReviewsBundleProvider(widget.truck.id));
      ref.invalidate(foodTruckProvider(widget.truck.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final truck = widget.truck;
    final hasPhotos = truck.photoUrls.isNotEmpty;
    // Reviews + the current user's own review used to be 2 independent
    // round trips; now 1 combined fetch (see truckReviewsBundleProvider).
    // Derived here as separate AsyncValues via whenData so the rest of this
    // screen's loading/error handling didn't need to change.
    final asyncReviewsBundle = ref.watch(truckReviewsBundleProvider(truck.id));
    final asyncReviews = asyncReviewsBundle.whenData((b) => b.reviews);
    final asyncMyReview = asyncReviewsBundle.whenData((b) => b.myReview);
    final user = ref.watch(authProvider).asData?.value;
    final isAuthenticated = user != null;
    final isOwnerOfTruck = user?.id == truck.ownerId;

    final canOrder =
        truck.isOpen && truck.ordersEnabled && truck.ordersAccepting;
    final currentWeekSpecials =
        ref.watch(truckCurrentWeekSpecialsProvider(truck.id)).asData?.value ??
        [];

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
                        if (ref
                                .watch(favoritedTruckIdsProvider)
                                .asData
                                ?.value
                                .contains(truck.id) ??
                            false)
                          AnnouncementBellButton(truckId: truck.id),
                        IconButton(
                          tooltip:
                              (ref
                                      .watch(favoritedTruckIdsProvider)
                                      .asData
                                      ?.value
                                      .contains(truck.id) ??
                                  false)
                              ? 'Remove from favorites'
                              : 'Add to favorites',
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              (ref
                                          .watch(favoritedTruckIdsProvider)
                                          .asData
                                          ?.value
                                          .contains(truck.id) ??
                                      false)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              key: ValueKey(
                                ref
                                    .watch(favoritedTruckIdsProvider)
                                    .asData
                                    ?.value
                                    .contains(truck.id),
                              ),
                              color: Colors.white,
                            ),
                          ),
                          onPressed: () => ref
                              .read(favoritedTruckIdsProvider.notifier)
                              .toggle(truck.id),
                        ),
                      ]
                    : null,
                flexibleSpace: FlexibleSpaceBar(
                  background: hasPhotos
                      ? PhotoCarousel(
                          urls: truck.photoUrls,
                          controller: _pageController,
                          currentIndex: _currentPhoto,
                          onPageChanged: (i) =>
                              setState(() => _currentPhoto = i),
                        )
                      : LogoHero(logoUrl: truck.logoUrl),
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
                                Text(
                                  truck.cuisineType,
                                  style: AppTextStyles.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                FollowerCount(truckId: truck.id),
                              ],
                            ),
                          ),
                          OpenBadge(isOpen: truck.isOpen),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      GestureDetector(
                        onTap: _scrollToReviews,
                        child: Row(
                          children: [
                            StarRatingWidget(
                              rating: truck.averageRating,
                              size: 16,
                              showValue: false,
                            ),
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
                      if (isAuthenticated && truck.privateEventsEnabled) ...[
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
                      if (truck.description != null &&
                          truck.description!.isNotEmpty) ...[
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
              // Mobile businesses don't keep a recurring weekly schedule (their
              // real schedule is whatever they announce week-to-week via
              // planned_locations), so a leftover operating_hours row — from
              // before switching to mobile, or just never cleared — would show
              // a stale, misleading schedule here if we didn't gate on isFixed.
              if (truck.isFixed && truck.operatingHours.isNotEmpty && !truck.hoursHidden) ...[
                const SectionSpacer(),
                SliverToBoxAdapter(
                  child: Section(
                    title: 'Hours',
                    child: HoursTable(hours: truck.operatingHours),
                  ),
                ),
              ],

              const SectionSpacer(),

              // ── This Week's Specials ─────────────────────────────────────────
              // Only the current calendar week's specials — computed from the
              // real date server-side, so anything an owner entered ahead of
              // time for a future week simply isn't in this result yet.
              if (currentWeekSpecials.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Section(
                    title: "This Week's Specials",
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: collapseConsecutiveSpecials(currentWeekSpecials)
                          .map((r) {
                            final priceStr = r.price == null
                                ? ''
                                : '  —  \$${r.price! == r.price!.roundToDouble() ? r.price!.toStringAsFixed(0) : r.price!.toStringAsFixed(2)}';
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              child: Text(
                                '${r.dayRangeLabel}: ${r.title}$priceStr',
                                style: AppTextStyles.bodySmall,
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ),
                ),
                const SectionSpacer(),
              ],

              // ── Order Now ────────────────────────────────────────────────────
              // ── Menu ─────────────────────────────────────────────────────────
              if (truck.menuItems.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Section(
                    title: 'Menu',
                    child: MenuGrid(
                      items: truck.menuItems,
                      canOrder: canOrder,
                      categoryOrder: truck.orderedCategoryNames,
                    ),
                  ),
                ),
                const SectionSpacer(),
              ],

              if (truck.menuItems.isEmpty &&
                  truck.menuPdfUrl == null &&
                  truck.menuImageUrl == null)
                SliverToBoxAdapter(
                  child: Section(
                    title: 'Menu',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.lg,
                      ),
                      child: Center(
                        child: Text(
                          'Menu not available yet',
                          style: AppTextStyles.bodySmall,
                        ),
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
                const SectionSpacer(),
                SliverToBoxAdapter(child: SocialSection(truck: truck)),
              ],

              const SectionSpacer(),

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
                            data: (myReview) =>
                                myReview == null && !isOwnerOfTruck
                                ? TextButton(
                                    onPressed: isAuthenticated
                                        ? () => _openReviewSheet(null)
                                        : () => _showLoginPrompt(context),
                                    child: Text(
                                      'Write a Review',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
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
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Text(
                          'Could not load reviews',
                          style: AppTextStyles.bodySmall,
                        ),
                        data: (reviews) {
                          if (reviews.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.lg,
                              ),
                              child: Center(
                                child: Text(
                                  'No reviews yet — be the first!',
                                  style: AppTextStyles.bodySmall,
                                ),
                              ),
                            );
                          }
                          final filtered = _filterRating == null
                              ? reviews
                              : reviews
                                    .where((r) => r.rating == _filterRating)
                                    .toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ReviewFilter(
                                selected: _filterRating,
                                onSelected: (v) =>
                                    setState(() => _filterRating = v),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              if (filtered.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.lg,
                                  ),
                                  child: Center(
                                    child: Text(
                                      'No ${_filterRating!}-star reviews yet',
                                      style: AppTextStyles.bodySmall,
                                    ),
                                  ),
                                )
                              else
                                ...filtered.map((r) {
                                  final isOwn = r.userId == user?.id;
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: AppSpacing.sm,
                                    ),
                                    child: ReviewCard(
                                      review: r,
                                      isOwn: isOwn,
                                      isOwnerOfTruck: isOwnerOfTruck,
                                      onEdit: isOwn
                                          ? () => _openReviewSheet(r)
                                          : null,
                                      onDelete: isOwn
                                          ? () => _deleteReview(r.id)
                                          : null,
                                      onReply: isOwnerOfTruck
                                          ? () => _replyToReview(r)
                                          : null,
                                      onEditReply: isOwnerOfTruck
                                          ? () => _replyToReview(
                                              r,
                                              existing: r.ownerResponse,
                                            )
                                          : null,
                                      onDeleteReply: isOwnerOfTruck
                                          ? () => _deleteOwnerResponse(r)
                                          : null,
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

              if (canOrder)
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
            ],
          ),
          if (canOrder)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingCartBar(truck: truck),
            ),
        ],
      ),
    );
  }

  void _showLoginPrompt(BuildContext context) {
    showTabAwareModalBottomSheet<void>(
      context: context,
      tabIndex: 0,
      backgroundColor: Colors.transparent,
      builder: (_) => const SignInPromptSheet(),
    );
  }
}
