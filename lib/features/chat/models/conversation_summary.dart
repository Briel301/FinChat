import 'package:flutter/foundation.dart';

/// Modelo de dominio inmutable que representa el resumen de una conversación 1 a 1
/// para ser presentado en la bandeja de entrada (Inbox).
@immutable
class ConversationSummary {
  /// Identificador único de la sala de conversación.
  final String chatId;

  /// Identificador del interlocutor en la sala 1 a 1.
  final String otherUserId;

  /// Nombre de usuario del interlocutor (@username).
  final String otherUsername;

  /// Nombre completo o alias del interlocutor (opcional).
  final String? otherFullName;

  /// URL pública de la imagen de perfil del interlocutor (opcional).
  final String? otherAvatarUrl;

  /// Texto del último mensaje enviado o recibido en el chat.
  final String lastMessageContent;

  /// Marca de tiempo del último mensaje para orden cronológico descendente.
  final DateTime lastMessageTime;

  /// Cantidad de mensajes pendientes de lectura para el usuario actual.
  final int unreadCount;

  const ConversationSummary({
    required this.chatId,
    required this.otherUserId,
    required this.otherUsername,
    this.otherFullName,
    this.otherAvatarUrl,
    required this.lastMessageContent,
    required this.lastMessageTime,
    this.unreadCount = 0,
  });

  /// Retorna una copia inmutable con los valores especificados reemplazados.
  ConversationSummary copyWith({
    String? chatId,
    String? otherUserId,
    String? otherUsername,
    String? otherFullName,
    String? otherAvatarUrl,
    String? lastMessageContent,
    DateTime? lastMessageTime,
    int? unreadCount,
  }) {
    return ConversationSummary(
      chatId: chatId ?? this.chatId,
      otherUserId: otherUserId ?? this.otherUserId,
      otherUsername: otherUsername ?? this.otherUsername,
      otherFullName: otherFullName ?? this.otherFullName,
      otherAvatarUrl: otherAvatarUrl ?? this.otherAvatarUrl,
      lastMessageContent: lastMessageContent ?? this.lastMessageContent,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  /// Deserialización segura desde Map (PostgREST RPC / vista SQL / almacenamiento local).
  factory ConversationSummary.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic dateValue) {
      if (dateValue is DateTime) return dateValue.toUtc();
      if (dateValue is String) {
        return DateTime.tryParse(dateValue)?.toUtc() ?? DateTime.now().toUtc();
      }
      return DateTime.now().toUtc();
    }

    int parseUnread(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return ConversationSummary(
      chatId: (map['chat_id'] ?? map['chatId'] ?? '').toString(),
      otherUserId: (map['other_user_id'] ?? map['otherUserId'] ?? '').toString(),
      otherUsername: (map['other_username'] ?? map['otherUsername'] ?? '').toString(),
      otherFullName: map['other_full_name'] as String? ?? map['otherFullName'] as String?,
      otherAvatarUrl: map['other_avatar_url'] as String? ?? map['otherAvatarUrl'] as String?,
      lastMessageContent: (map['last_message_content'] ?? map['lastMessageContent'] ?? '').toString(),
      lastMessageTime: parseDate(
        map['last_message_time'] ?? map['lastMessageTime'] ?? map['updated_at'],
      ),
      unreadCount: parseUnread(map['unread_count'] ?? map['unreadCount']),
    );
  }

  /// Serialización a Map estándar compatible con almacenamiento local y JSON.
  Map<String, dynamic> toMap() {
    return {
      'chat_id': chatId,
      'other_user_id': otherUserId,
      'other_username': otherUsername,
      'other_full_name': otherFullName,
      'other_avatar_url': otherAvatarUrl,
      'last_message_content': lastMessageContent,
      'last_message_time': lastMessageTime.toUtc().toIso8601String(),
      'unread_count': unreadCount,
    };
  }

  /// Serialización directa a Map para interoperabilidad con APIs JSON.
  Map<String, dynamic> toJson() => toMap();

  /// Deserialización directa desde JSON.
  factory ConversationSummary.fromJson(Map<String, dynamic> json) =>
      ConversationSummary.fromMap(json);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationSummary &&
          runtimeType == other.runtimeType &&
          chatId == other.chatId &&
          otherUserId == other.otherUserId &&
          otherUsername == other.otherUsername &&
          otherFullName == other.otherFullName &&
          otherAvatarUrl == other.otherAvatarUrl &&
          lastMessageContent == other.lastMessageContent &&
          lastMessageTime == other.lastMessageTime &&
          unreadCount == other.unreadCount;

  @override
  int get hashCode =>
      chatId.hashCode ^
      otherUserId.hashCode ^
      otherUsername.hashCode ^
      (otherFullName?.hashCode ?? 0) ^
      (otherAvatarUrl?.hashCode ?? 0) ^
      lastMessageContent.hashCode ^
      lastMessageTime.hashCode ^
      unreadCount.hashCode;

  @override
  String toString() {
    return 'ConversationSummary(chatId: $chatId, otherUserId: $otherUserId, '
        'otherUsername: $otherUsername, unreadCount: $unreadCount, '
        'lastMessageContent: $lastMessageContent, lastMessageTime: $lastMessageTime)';
  }
}
