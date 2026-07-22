import '../../../features/food_trucks/models/operating_hours.dart';
import '../../../features/food_trucks/models/menu_category.dart';
import '../../../features/food_trucks/models/menu_item.dart';

class FoodTruck {
  const FoodTruck({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.cuisineType,
    this.slug,
    this.description,
    this.logoUrl,
    this.photoUrls = const [],
    this.menuPdfUrl,
    this.menuImageUrl,
    this.address,
    this.latitude,
    this.longitude,
    this.locationUpdatedAt,
    this.sessionStartedAt,
    required this.averageRating,
    required this.reviewCount,
    required this.isOpen,
    required this.isActive,
    this.operatingHours = const [],
    this.menuItems = const [],
    this.menuCategories = const [],
    this.socialInstagram,
    this.socialTiktok,
    this.socialFacebook,
    this.socialTwitter,
    this.socialYoutube,
    this.websiteUrl,
    this.cancellationPolicyHours,
    this.ordersEnabled = false,
    this.ordersAccepting = true,
    this.openedByUserId,
    this.businessType = 'mobile',
    this.hasEverOpened = false,
    this.autoHoursEnabled = false,
    this.hoursHidden = false,
    this.taxRatePercent,
    this.autoAcceptOrders = false,
    this.autoMarkReady = false,
    this.autoMarkReadyDelayMinutes = 0,
    this.autoMarkComplete = false,
    this.autoMarkCompleteDelayMinutes = 0,
    this.privateEventsEnabled = true,
  });

  final String id;
  final String ownerId;
  final String name;
  final String cuisineType;
  // Nullable defensively even though the DB trigger (see
  // supabase/migrations/20260710213921_add_food_trucks_slug.sql) generates
  // one for every new row -- older rows or an unforeseen direct-insert path
  // could theoretically still lack it, and callers (share link building)
  // should degrade gracefully rather than build a broken "visit.farlo.app/null"
  // URL.
  final String? slug;
  final String? description;
  final String? logoUrl;
  final List<String> photoUrls;
  final String? menuPdfUrl;
  final String? menuImageUrl;
  final String? address;
  final String? socialInstagram;
  final String? socialTiktok;
  final String? socialFacebook;
  final String? socialTwitter;
  final String? socialYoutube;
  final String? websiteUrl;
  final int? cancellationPolicyHours;
  final bool ordersEnabled;
  final bool ordersAccepting;
  final String? openedByUserId;
  final String businessType;
  final bool hasEverOpened;
  final bool autoHoursEnabled;
  final bool hoursHidden;
  final double? taxRatePercent;
  final bool autoAcceptOrders;
  final bool autoMarkReady;
  final int autoMarkReadyDelayMinutes;
  final bool autoMarkComplete;
  final int autoMarkCompleteDelayMinutes;
  final bool privateEventsEnabled;

  bool get isFixed => businessType == 'fixed';
  final double? latitude;
  final double? longitude;
  final DateTime? locationUpdatedAt;
  final DateTime? sessionStartedAt;
  final double averageRating;
  final int reviewCount;
  final bool isOpen;
  final bool isActive;
  final List<OperatingHours> operatingHours;
  final List<MenuItem> menuItems;
  final List<MenuCategory> menuCategories;

  // Category order used to be implicit (whichever category's first item had
  // the lowest global sort_order) with no way to change it. menu_categories
  // now carries an explicit order, but a brand-new custom category typed into
  // the menu-item form may not have a row there yet (created lazily) — so any
  // category name found on an item but missing from menuCategories is
  // appended at the end, in first-appearance order, rather than dropped.
  List<String> get orderedCategoryNames {
    final known = [...menuCategories]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final names = known.map((c) => c.name).toList();
    final seen = names.toSet();
    for (final item in menuItems) {
      if (seen.add(item.category)) names.add(item.category);
    }
    return names;
  }

  factory FoodTruck.fromMap(Map<String, dynamic> map) {
    List<OperatingHours> hours = [];
    if (map['operating_hours'] != null) {
      hours = (map['operating_hours'] as List)
          .map((e) => OperatingHours.fromMap(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
    }

    List<MenuItem> items = [];
    if (map['menu_items'] != null) {
      items = (map['menu_items'] as List)
          .map((e) => MenuItem.fromMap(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    List<MenuCategory> categories = [];
    if (map['menu_categories'] != null) {
      categories = (map['menu_categories'] as List)
          .map((e) => MenuCategory.fromMap(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    return FoodTruck(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      name: map['name'] as String,
      cuisineType: map['cuisine_type'] as String,
      slug: map['slug'] as String?,
      description: map['description'] as String?,
      logoUrl: map['logo_url'] as String?,
      photoUrls: (map['photo_urls'] as List?)?.cast<String>() ?? const [],
      menuPdfUrl: map['menu_pdf_url'] as String?,
      menuImageUrl: map['menu_image_url'] as String?,
      address: map['address'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      locationUpdatedAt: map['location_updated_at'] != null
          ? DateTime.parse(map['location_updated_at'] as String)
          : null,
      sessionStartedAt: map['session_started_at'] != null
          ? DateTime.parse(map['session_started_at'] as String)
          : null,
      averageRating: (map['average_rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
      isOpen: map['is_open'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? false,
      operatingHours: hours,
      menuItems: items,
      menuCategories: categories,
      socialInstagram: map['social_instagram'] as String?,
      socialTiktok: map['social_tiktok'] as String?,
      socialFacebook: map['social_facebook'] as String?,
      socialTwitter: map['social_twitter'] as String?,
      socialYoutube: map['social_youtube'] as String?,
      websiteUrl: map['website_url'] as String?,
      cancellationPolicyHours: map['cancellation_policy_hours'] as int?,
      ordersEnabled: map['orders_enabled'] as bool? ?? false,
      ordersAccepting: map['orders_accepting'] as bool? ?? true,
      openedByUserId: map['opened_by_user_id'] as String?,
      businessType: map['business_type'] as String? ?? 'mobile',
      hasEverOpened: map['has_ever_opened'] as bool? ?? false,
      autoHoursEnabled: map['auto_hours_enabled'] as bool? ?? false,
      hoursHidden: map['hours_hidden'] as bool? ?? false,
      taxRatePercent: (map['tax_rate_percent'] as num?)?.toDouble(),
      autoAcceptOrders: map['auto_accept_orders'] as bool? ?? false,
      autoMarkReady: map['auto_mark_ready'] as bool? ?? false,
      autoMarkReadyDelayMinutes: map['auto_mark_ready_delay_minutes'] as int? ?? 0,
      autoMarkComplete: map['auto_mark_complete'] as bool? ?? false,
      autoMarkCompleteDelayMinutes: map['auto_mark_complete_delay_minutes'] as int? ?? 0,
      privateEventsEnabled: map['private_events_enabled'] as bool? ?? true,
    );
  }

  static const _unset = Object();

  FoodTruck copyWith({
    String? name,
    String? cuisineType,
    String? description,
    String? logoUrl,
    List<String>? photoUrls,
    String? address,
    bool? isOpen,
    bool? ordersEnabled,
    bool? ordersAccepting,
    double? latitude,
    double? longitude,
    DateTime? locationUpdatedAt,
    Object? sessionStartedAt = _unset,
    Object? openedByUserId = _unset,
    List<OperatingHours>? operatingHours,
    List<MenuItem>? menuItems,
    List<MenuCategory>? menuCategories,
    String? businessType,
    bool? hasEverOpened,
    bool? autoHoursEnabled,
    bool? hoursHidden,
    Object? taxRatePercent = _unset,
    bool? autoAcceptOrders,
    bool? autoMarkReady,
    int? autoMarkReadyDelayMinutes,
    bool? autoMarkComplete,
    int? autoMarkCompleteDelayMinutes,
    bool? privateEventsEnabled,
  }) {
    return FoodTruck(
      id: id,
      ownerId: ownerId,
      name: name ?? this.name,
      cuisineType: cuisineType ?? this.cuisineType,
      slug: slug,
      description: description ?? this.description,
      logoUrl: logoUrl ?? this.logoUrl,
      photoUrls: photoUrls ?? this.photoUrls,
      menuPdfUrl: menuPdfUrl,
      menuImageUrl: menuImageUrl,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationUpdatedAt: locationUpdatedAt ?? this.locationUpdatedAt,
      sessionStartedAt: sessionStartedAt == _unset
          ? this.sessionStartedAt
          : sessionStartedAt as DateTime?,
      averageRating: averageRating,
      reviewCount: reviewCount,
      isOpen: isOpen ?? this.isOpen,
      ordersEnabled: ordersEnabled ?? this.ordersEnabled,
      ordersAccepting: ordersAccepting ?? this.ordersAccepting,
      openedByUserId: openedByUserId == _unset
          ? this.openedByUserId
          : openedByUserId as String?,
      isActive: isActive,
      operatingHours: operatingHours ?? this.operatingHours,
      menuItems: menuItems ?? this.menuItems,
      menuCategories: menuCategories ?? this.menuCategories,
      cancellationPolicyHours: cancellationPolicyHours,
      businessType: businessType ?? this.businessType,
      hasEverOpened: hasEverOpened ?? this.hasEverOpened,
      autoHoursEnabled: autoHoursEnabled ?? this.autoHoursEnabled,
      hoursHidden: hoursHidden ?? this.hoursHidden,
      taxRatePercent: taxRatePercent == _unset
          ? this.taxRatePercent
          : taxRatePercent as double?,
      autoAcceptOrders: autoAcceptOrders ?? this.autoAcceptOrders,
      autoMarkReady: autoMarkReady ?? this.autoMarkReady,
      autoMarkReadyDelayMinutes: autoMarkReadyDelayMinutes ?? this.autoMarkReadyDelayMinutes,
      autoMarkComplete: autoMarkComplete ?? this.autoMarkComplete,
      autoMarkCompleteDelayMinutes: autoMarkCompleteDelayMinutes ?? this.autoMarkCompleteDelayMinutes,
      privateEventsEnabled: privateEventsEnabled ?? this.privateEventsEnabled,
    );
  }
}
