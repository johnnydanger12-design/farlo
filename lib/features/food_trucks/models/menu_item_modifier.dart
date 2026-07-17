// A per-item customization option an owner defines — e.g. a burger's
// Pickles/Mayo/Ketchup/Mustard. includedByDefault=true + priceDelta=0 is a
// free ingredient a customer can remove; includedByDefault=false +
// priceDelta>0 is a paid add-on a customer can add.
class MenuItemModifier {
  const MenuItemModifier({
    required this.id,
    required this.menuItemId,
    required this.name,
    required this.priceDelta,
    required this.includedByDefault,
    required this.sortOrder,
  });

  final String id;
  final String menuItemId;
  final String name;
  final double priceDelta;
  final bool includedByDefault;
  final int sortOrder;

  factory MenuItemModifier.fromMap(Map<String, dynamic> map) {
    return MenuItemModifier(
      id: map['id'] as String,
      menuItemId: map['menu_item_id'] as String,
      name: map['name'] as String,
      priceDelta: (map['price_delta'] as num?)?.toDouble() ?? 0,
      includedByDefault: map['included_by_default'] as bool? ?? true,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }
}
