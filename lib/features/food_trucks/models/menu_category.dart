class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.truckId,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String truckId;
  final String name;
  final int sortOrder;

  factory MenuCategory.fromMap(Map<String, dynamic> map) {
    return MenuCategory(
      id: map['id'] as String,
      truckId: map['truck_id'] as String,
      name: map['name'] as String,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  MenuCategory copyWith({int? sortOrder}) {
    return MenuCategory(
      id: id,
      truckId: truckId,
      name: name,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
