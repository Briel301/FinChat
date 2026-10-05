/// Representa el estado de autenticación y verificación de seguridad del usuario.
class UserSession {
  final String userId;
  final String email;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final bool isMfaRequired;
  final bool isMfaVerified;
  final String? token;

  const UserSession({
    required this.userId,
    required this.email,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.isMfaRequired = true,
    this.isMfaVerified = false,
    this.token,
  });

  bool get isAuthenticated => userId.isNotEmpty && (!isMfaRequired || isMfaVerified);

  UserSession copyWith({
    String? userId,
    String? email,
    String? username,
    String? fullName,
    String? avatarUrl,
    bool? isMfaRequired,
    bool? isMfaVerified,
    String? token,
  }) {
    return UserSession(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isMfaRequired: isMfaRequired ?? this.isMfaRequired,
      isMfaVerified: isMfaVerified ?? this.isMfaVerified,
      token: token ?? this.token,
    );
  }

  factory UserSession.empty() {
    return const UserSession(
      userId: '',
      email: '',
      username: '',
      isMfaRequired: true,
      isMfaVerified: false,
    );
  }
}
