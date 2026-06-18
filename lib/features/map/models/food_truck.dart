import '../../../features/food_trucks/models/operating_hours.dart';
import '../../../features/food_trucks/models/menu_item.dart';

class FoodTruck {
  const FoodTruck({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.cuisineType,
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
  });

  final String id;
  final String ownerId;
  final String name;
  final String cuisineType;
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

    return FoodTruck(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      name: map['name'] as String,
      cuisineType: map['cuisine_type'] as String,
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
    String? businessType,
  }) {
    return FoodTruck(
      id: id,
      ownerId: ownerId,
      name: name ?? this.name,
      cuisineType: cuisineType ?? this.cuisineType,
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
      cancellationPolicyHours: cancellationPolicyHours,
      businessType: businessType ?? this.businessType,
    );
  }
}
