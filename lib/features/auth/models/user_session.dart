import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Representa una sesión de usuario inmutable y autenticada en FinChat.
///
/// Aplica una política de bloqueo estricto: ningún usuario se considera completamente
/// autenticado para acceder al chat si [isMfaVerified] es `false`.
@immutable
class UserSession {
  /// Identificador único UUID del usuario en Supabase (auth.users.id).
  final String userId;

  /// Correo electrónico registrado del usuario.
  final String email;

  /// Nombre de usuario único para menciones y búsqueda exacta sin SIM (@usuario).
  final String username;

  /// Nombre completo o alias visible del usuario (opcional).
  final String? fullName;

  /// URL del avatar almacenado en Supabase Storage (opcional).
  final String? avatarUrl;

  /// Token JWT de acceso activo emitido por GoTrue / Supabase Auth.
  final String? accessToken;

  /// Indica si el segundo factor de autenticación (OTP de 6 dígitos) fue superado.
  final bool isMfaVerified;

  /// Indica si este perfil exige desafío MFA obligatorio (por defecto true según MoSCoW).
  final bool isMfaRequired;

  /// Fecha y hora de creación de la cuenta o emisión de la sesión.
  final DateTime createdAt;

  /// Constructor principal inmutable.
  UserSession({
    required this.userId,
    required this.email,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.accessToken,
    this.isMfaVerified = false,
    this.isMfaRequired = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Alias de conveniencia retrocompatible para [accessToken].
  String? get token => accessToken;

  /// Bloqueo estricto: El usuario solo es considerado autenticado si posee un ID
  /// válido y ha verificado satisfactoriamente su factor MFA.
  bool get isAuthenticated => userId.isNotEmpty && isMfaVerified;

  /// Crea una instancia vacía sin autenticar.
  factory UserSession.empty() {
    return UserSession(
      userId: '',
      email: '',
      username: '',
      isMfaVerified: false,
      isMfaRequired: true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  /// Factory para construir una sesión a partir de entidades de Supabase (`User` y `Session`).
  ///
  /// Extrae `username` y `full_name` de los metadatos (`user_metadata`), garantizando
  /// compatibilidad con la creación atómica de perfiles en PostgreSQL.
  factory UserSession.fromSupabase({
    required User user,
    Session? session,
    bool isMfaVerified = false,
    bool isMfaRequired = true,
  }) {
    final meta = user.userMetadata ?? {};
    final usernameMeta = meta['username'] as String?;
    final fallbackUsername = (user.email != null && user.email!.contains('@'))
        ? user.email!.split('@').first
        : user.id;

    return UserSession(
      userId: user.id,
      email: user.email ?? '',
      username: (usernameMeta != null && usernameMeta.isNotEmpty)
          ? usernameMeta.trim().toLowerCase()
          : fallbackUsername.trim().toLowerCase(),
      fullName: meta['full_name'] as String?,
      avatarUrl: meta['avatar_url'] as String?,
      accessToken: session?.accessToken,
      isMfaVerified: isMfaVerified,
      isMfaRequired: isMfaRequired,
      createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now(),
    );
  }

  /// Construye una instancia a partir de un mapa serializado (JSON o almacenamiento local).
  factory UserSession.fromMap(Map<String, dynamic> map) {
    DateTime parsedDate;
    final rawDate = map['created_at'] ?? map['createdAt'];
    if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else if (rawDate is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
    } else {
      parsedDate = DateTime.now();
    }

    return UserSession(
      userId: (map['user_id'] ?? map['userId'] ?? '') as String,
      email: (map['email'] ?? '') as String,
      username: (map['username'] ?? '') as String,
      fullName: (map['full_name'] ?? map['fullName']) as String?,
      avatarUrl: (map['avatar_url'] ?? map['avatarUrl']) as String?,
      accessToken: (map['access_token'] ?? map['accessToken'] ?? map['token']) as String?,
      isMfaVerified: (map['is_mfa_verified'] ?? map['isMfaVerified'] ?? false) as bool,
      isMfaRequired: (map['is_mfa_required'] ?? map['isMfaRequired'] ?? true) as bool,
      createdAt: parsedDate,
    );
  }

  /// Serializa los datos de la sesión para persistencia en SharedPreferences o caché local.
  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'email': email,
      'username': username,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'access_token': accessToken,
      'is_mfa_verified': isMfaVerified,
      'is_mfa_required': isMfaRequired,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Retorna una copia con propiedades modificadas preservando la inmutabilidad.
  UserSession copyWith({
    String? userId,
    String? email,
    String? username,
    String? fullName,
    String? avatarUrl,
    String? accessToken,
    bool? isMfaVerified,
    bool? isMfaRequired,
    DateTime? createdAt,
  }) {
    return UserSession(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      accessToken: accessToken ?? this.accessToken,
      isMfaVerified: isMfaVerified ?? this.isMfaVerified,
      isMfaRequired: isMfaRequired ?? this.isMfaRequired,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserSession &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          email == other.email &&
          username == other.username &&
          accessToken == other.accessToken &&
          isMfaVerified == other.isMfaVerified &&
          isMfaRequired == other.isMfaRequired &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      userId.hashCode ^
      email.hashCode ^
      username.hashCode ^
      accessToken.hashCode ^
      isMfaVerified.hashCode ^
      isMfaRequired.hashCode ^
      createdAt.hashCode;

  @override
  String toString() {
    return 'UserSession(userId: $userId, username: @$username, email: $email, isMfaVerified: $isMfaVerified)';
  }
}
