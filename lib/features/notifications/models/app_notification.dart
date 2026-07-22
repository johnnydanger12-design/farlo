class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.relatedId,
    this.imageUrl,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final bool read;
  final String? relatedId;
  final String? imageUrl;
  final DateTime createdAt;

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        type: m['type'] as String,
        title: m['title'] as String,
        body: m['body'] as String,
        read: m['read'] as bool,
        relatedId: m['related_id'] as String?,
        imageUrl: m['image_url'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        read: read ?? this.read,
        relatedId: relatedId,
        imageUrl: imageUrl,
        createdAt: createdAt,
      );
}
