// A draft menu item parsed from a photo/PDF upload, before the owner has
// reviewed/confirmed it — distinct from MenuItem, which represents a row
// that actually exists in menu_items (has an id, isAvailable, etc).
class ParsedMenuItem {
  ParsedMenuItem({
    required this.name,
    this.description,
    required this.price,
    required this.category,
  });

  String name;
  String? description;
  double price;
  String category;

  factory ParsedMenuItem.fromMap(Map<String, dynamic> map) {
    return ParsedMenuItem(
      name: map['name'] as String? ?? '',
      description: (map['description'] as String?)?.trim().isEmpty ?? true ? null : map['description'] as String,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      category: map['category'] as String? ?? 'Mains',
    );
  }
}
