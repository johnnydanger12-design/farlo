// One day's purchase window for a menu category. A category can have
// several rows (e.g. Blue Plate Special: 11am-2pm AND 5pm-9pm on the same
// day) — a category with zero rows has no restriction at all and is
// purchasable whenever the truck itself is open.
class CategoryPurchaseWindow {
  const CategoryPurchaseWindow({
    required this.id,
    required this.truckId,
    required this.categoryName,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final String truckId;
  final String categoryName;
  final int dayOfWeek; // 0 = Sunday
  final String startTime; // "HH:MM"
  final String endTime;

  static const List<String> dayAbbrevs = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  static String formatTime(String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return minute == '00' ? '$displayHour $period' : '$displayHour:$minute $period';
  }

  factory CategoryPurchaseWindow.fromMap(Map<String, dynamic> map) {
    String parseTime(dynamic val) => (val as String).substring(0, 5);
    return CategoryPurchaseWindow(
      id: map['id'] as String,
      truckId: map['truck_id'] as String,
      categoryName: map['category_name'] as String,
      dayOfWeek: map['day_of_week'] as int,
      startTime: parseTime(map['start_time']),
      endTime: parseTime(map['end_time']),
    );
  }
}
