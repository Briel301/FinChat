import 'package:flutter/foundation.dart';

/// Entidad inmutable que representa el perfil público y metadatos de un usuario en FinChat.
@immutable
class UserProfile {
  /// Identificador único UUID del usuario (clave primaria vinculada a auth.users).
  final String id;

  /// Nombre de usuario único para menciones y búsqueda exacta sin SIM (@usuario).
  final String username;

  /// Correo electrónico asociado al perfil.
  final String email;

  /// Nombre completo o alias para mostrar en pantalla.
  final String fullName;

  /// URL de la imagen de avatar en Supabase Storage (opcional).
  final String? avatarUrl;

  /// Biografía o estado del usuario (máximo 160 caracteres).
  final String? bio;

  /// Fecha y hora de creación del perfil.
  final DateTime createdAt;

  /// Estado de presencia o conexión (para visualización UI).
  final bool isOnline;

  const UserProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    this.bio,
    required this.createdAt,
    this.isOnline = false,
  });

  /// Construye una entidad a partir de una fila retornada por PostgREST / Supabase.
  factory UserProfile.fromMap(Map<String, dynamic> map) {
    DateTime parsedDate;
    final rawDate = map['created_at'] ?? map['createdAt'];
    if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else if (rawDate is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
    } else {
      parsedDate = DateTime.now();
    }

    final rawUsername = (map['username'] ?? '') as String;
    final rawEmail = (map['email'] ?? '') as String;
    final rawFullName = map['full_name'] as String? ?? map['fullName'] as String?;

    return UserProfile(
      id: (map['id'] ?? '') as String,
      username: rawUsername,
      email: rawEmail,
      fullName: (rawFullName != null && rawFullName.isNotEmpty) ? rawFullName : rawUsername,
      avatarUrl: map['avatar_url'] as String? ?? map['avatarUrl'] as String?,
      bio: map['bio'] as String?,
      createdAt: parsedDate,
      isOnline: (map['is_online'] ?? map['isOnline'] ?? false) as bool,
    );
  }

  /// Alias de conveniencia retrocompatible con [fromMap].
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile.fromMap(json);

  /// Serializa los datos del perfil a un mapa para Supabase o caché local.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'bio': bio,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_online': isOnline,
    };
  }

  /// Alias de conveniencia retrocompatible con [toMap].
  Map<String, dynamic> toJson() => toMap();

  /// Retorna una copia con los campos especificados modificados preservando la inmutabilidad.
  UserProfile copyWith({
    String? id,
    String? username,
    String? email,
    String? fullName,
    String? avatarUrl,
    String? bio,
    DateTime? createdAt,
    bool? isOnline,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      createdAt: createdAt ?? this.createdAt,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          username == other.username &&
          email == other.email &&
          fullName == other.fullName &&
          avatarUrl == other.avatarUrl &&
          bio == other.bio &&
          createdAt == other.createdAt &&
          isOnline == other.isOnline;

  @override
  int get hashCode =>
      id.hashCode ^
      username.hashCode ^
      email.hashCode ^
      fullName.hashCode ^
      avatarUrl.hashCode ^
      bio.hashCode ^
      createdAt.hashCode ^
      isOnline.hashCode;

  @override
  String toString() {
    return 'UserProfile(id: $id, username: @$username, email: $email, fullName: $fullName)';
  }
}
