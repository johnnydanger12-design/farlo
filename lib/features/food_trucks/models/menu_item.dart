class MenuItem {
  const MenuItem({
    required this.id,
    required this.truckId,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    required this.category,
    required this.isAvailable,
    required this.sortOrder,
  });

  final String id;
  final String truckId;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final String category;
  final bool isAvailable;
  final int sortOrder;

  String get priceDisplay => '\$${price.toStringAsFixed(2)}';

  factory MenuItem.fromMap(Map<String, dynamic> map) {
    return MenuItem(
      id: map['id'] as String,
      truckId: map['truck_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: (map['price'] as num).toDouble(),
      imageUrl: map['image_url'] as String?,
      category: map['category'] as String? ?? 'Mains',
      isAvailable: map['is_available'] as bool? ?? true,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'truck_id': truckId,
    'name': name,
    'description': description,
    'price': price,
    'image_url': imageUrl,
    'category': category,
    'is_available': isAvailable,
    'sort_order': sortOrder,
  };

  MenuItem copyWith({
    String? name,
    String? description,
    double? price,
    String? imageUrl,
    String? category,
    bool? isAvailable,
    int? sortOrder,
  }) {
    return MenuItem(
      id: id,
      truckId: truckId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      isAvailable: isAvailable ?? this.isAvailable,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
