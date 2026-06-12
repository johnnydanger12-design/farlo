enum UserRole { consumer, owner }

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.avatarUrl,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final String? avatarUrl;
  final DateTime createdAt;

  bool get isOwner => role == UserRole.owner;

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      email: map['email'] as String,
      displayName: map['display_name'] as String,
      role: (map['role'] as String) == 'owner' ? UserRole.owner : UserRole.consumer,
      avatarUrl: map['avatar_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'role': role == UserRole.owner ? 'owner' : 'consumer',
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
  }
}
