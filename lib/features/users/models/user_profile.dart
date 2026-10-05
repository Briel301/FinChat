/// Entidad que representa el perfil público de un usuario.
class UserProfile {
  final String id;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final String? bio;
  final DateTime createdAt;
  final bool isOnline;

  const UserProfile({
    required this.id,
    required this.username,
    required this.fullName,
    this.avatarUrl,
    this.bio,
    required this.createdAt,
    this.isOnline = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      fullName: json['full_name'] as String? ?? json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : DateTime.now(),
      isOnline: json['is_online'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'bio': bio,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
