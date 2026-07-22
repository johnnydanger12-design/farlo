class WeeklySpecial {
  const WeeklySpecial({
    required this.id,
    required this.truckId,
    required this.eventDate,
    required this.title,
    this.price,
    required this.createdAt,
  });

  final String id;
  final String truckId;
  final DateTime eventDate;
  final String title;
  final double? price;
  final DateTime createdAt;

  factory WeeklySpecial.fromMap(Map<String, dynamic> m) => WeeklySpecial(
    id: m['id'] as String,
    truckId: m['truck_id'] as String,
    eventDate: DateTime.parse(m['event_date'] as String),
    title: m['title'] as String,
    price: (m['price'] as num?)?.toDouble(),
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
  );
}

// A run of one or more consecutive days sharing the same title+price,
// collapsed for display so a special entered identically on e.g. Mon-Fri
// (the only way to represent "runs through Friday" without a schema change —
// see collapseConsecutiveSpecials below) reads as one offer with a date
// range, not five separate-looking daily specials that happen to match.
class SpecialRange {
  const SpecialRange({
    required this.firstDate,
    required this.lastDate,
    required this.title,
    this.price,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  final double? price;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String get dayRangeLabel {
    final first = _dayNames[firstDate.weekday - 1];
    if (firstDate.year == lastDate.year &&
        firstDate.month == lastDate.month &&
        firstDate.day == lastDate.day) {
      return first;
    }
    return '$first–${_dayNames[lastDate.weekday - 1]}';
  }
}

// Input must already be sorted ascending by eventDate (both repository fetch
// methods already do this). Only merges genuinely adjacent calendar days —
// two non-consecutive days that happen to share a title/price (e.g. Mon and
// Thu both "Chicken Plate") are kept separate, since collapsing those would
// wrongly imply it ran through Tue/Wed too.
List<SpecialRange> collapseConsecutiveSpecials(List<WeeklySpecial> specials) {
  final ranges = <SpecialRange>[];
  for (final s in specials) {
    if (ranges.isNotEmpty) {
      final last = ranges.last;
      final isNextDay =
          s.eventDate.difference(last.lastDate).inDays == 1 &&
          last.title == s.title &&
          last.price == s.price;
      if (isNextDay) {
        ranges[ranges.length - 1] = SpecialRange(
          firstDate: last.firstDate,
          lastDate: s.eventDate,
          title: last.title,
          price: last.price,
        );
        continue;
      }
    }
    ranges.add(
      SpecialRange(
        firstDate: s.eventDate,
        lastDate: s.eventDate,
        title: s.title,
        price: s.price,
      ),
    );
  }
  return ranges;
}
