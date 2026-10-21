import 'package:flutter/foundation.dart';

/// Tipo de contenido soportado para los mensajes en FinChat.
enum MessageType {
  text,
  image,
  video,
  audio;

  static MessageType fromString(String? value) {
    if (value == null) return MessageType.text;
    return MessageType.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => MessageType.text,
    );
  }
}

/// Estados de entrega y lectura del mensaje.
enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed;

  static MessageStatus fromString(String? value) {
    if (value == null) return MessageStatus.sent;
    final normalized = value.toLowerCase();
    if (normalized == 'pending') return MessageStatus.sending;
    if (normalized == 'error' || normalized == 'failed') return MessageStatus.failed;
    return MessageStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse: () => MessageStatus.sent,
    );
  }
}

/// Alias para mantener retrocompatibilidad con referencias históricas.
@Deprecated('Usar MessageStatus en su lugar')
typedef MessageDeliveryStatus = MessageStatus;

/// Entidad de dominio inmutable que representa un mensaje individual dentro de un chat 1 a 1.
@immutable
class ChatMessage {
  /// Identificador único (UUIDv4 generado preferentemente en el cliente para Optimistic UI).
  final String id;

  /// Identificador de la conversación (sala) a la que pertenece el mensaje.
  final String chatId;

  /// Identificador del usuario remitente (referencia a profiles.id).
  final String senderId;

  /// Contenido textual del mensaje.
  final String content;

  /// Tipo de contenido (texto, imagen, video, audio).
  final MessageType type;

  /// URL remota del recurso multimedia alojado en Supabase Storage (opcional).
  final String? mediaUrl;

  /// Estado actual del mensaje en el flujo de envío/recepción.
  final MessageStatus status;

  /// Marca de tiempo de creación en formato UTC.
  final DateTime createdAt;

  /// Bandera para gestión de persistencia offline (false = almacenado localmente en cola).
  final bool isSynced;

  // --- Metadatos adicionales para multimedia y compatibilidad de interfaz ---
  final String? senderUsername;
  final int? fileSizeBytes;
  final int? durationSeconds;
  final bool? _isFromMe;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    this.type = MessageType.text,
    this.mediaUrl,
    this.status = MessageStatus.sent,
    required this.createdAt,
    this.isSynced = true,
    this.senderUsername,
    this.fileSizeBytes,
    this.durationSeconds,
    bool? isFromMe,
  }) : _isFromMe = isFromMe;

  /// Determina si el mensaje fue emitido por el usuario actual autenticado.
  /// Se utiliza para alinear las burbujas a la derecha (propios) o a la izquierda (interlocutor).
  bool isMine(String currentUserId) => senderId == currentUserId;

  /// Accesor de compatibilidad para vistas previas donde aún no se inyecta currentUserId.
  bool get isFromMe => _isFromMe ?? false;

  /// Accesor de compatibilidad para llamadas previas a [text].
  String get text => content;

  /// Accesor de compatibilidad para llamadas previas a [timestamp].
  DateTime get timestamp => createdAt;

  /// Retorna una copia inmutable con los valores especificados reemplazados.
  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? content,
    MessageType? type,
    String? mediaUrl,
    MessageStatus? status,
    DateTime? createdAt,
    bool? isSynced,
    String? senderUsername,
    int? fileSizeBytes,
    int? durationSeconds,
    bool? isFromMe,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
      senderUsername: senderUsername ?? this.senderUsername,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isFromMe: isFromMe ?? _isFromMe,
    );
  }

  /// Deserialización segura tolerante a respuestas de Supabase PostgREST y almacenamiento local.
  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic dateValue) {
      if (dateValue is DateTime) return dateValue.toUtc();
      if (dateValue is String) {
        return DateTime.tryParse(dateValue)?.toUtc() ?? DateTime.now().toUtc();
      }
      return DateTime.now().toUtc();
    }

    return ChatMessage(
      id: (map['id'] ?? '').toString(),
      chatId: (map['chat_id'] ?? map['chatId'] ?? '').toString(),
      senderId: (map['sender_id'] ?? map['senderId'] ?? '').toString(),
      content: (map['content'] ?? map['text'] ?? '').toString(),
      type: MessageType.fromString((map['message_type'] ?? map['type'])?.toString()),
      mediaUrl: map['media_url'] as String? ?? map['mediaUrl'] as String?,
      status: MessageStatus.fromString(map['status']?.toString()),
      createdAt: parseDate(map['created_at'] ?? map['timestamp'] ?? map['createdAt']),
      isSynced: map['is_synced'] as bool? ?? map['isSynced'] as bool? ?? true,
      senderUsername: map['sender_username'] as String? ?? map['senderUsername'] as String?,
      fileSizeBytes: (map['file_size_bytes'] ?? map['fileSizeBytes']) as int?,
      durationSeconds: (map['duration_seconds'] ?? map['durationSeconds']) as int?,
      isFromMe: map['is_from_me'] as bool? ?? map['isFromMe'] as bool?,
    );
  }

  /// Serialización a Map compatible con PostgreSQL (Supabase) y almacenamiento en caché local.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'sender_id': senderId,
      'content': content,
      'message_type': type.name,
      'media_url': mediaUrl,
      'status': status.name,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_synced': isSynced,
      if (senderUsername != null) 'sender_username': senderUsername,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
    };
  }

  /// Serialización directa a Map para interoperabilidad con APIs JSON.
  Map<String, dynamic> toJson() => toMap();

  /// Deserialización directa desde JSON.
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage.fromMap(json);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          chatId == other.chatId &&
          senderId == other.senderId &&
          content == other.content &&
          type == other.type &&
          mediaUrl == other.mediaUrl &&
          status == other.status &&
          createdAt == other.createdAt &&
          isSynced == other.isSynced;

  @override
  int get hashCode =>
      id.hashCode ^
      chatId.hashCode ^
      senderId.hashCode ^
      content.hashCode ^
      type.hashCode ^
      (mediaUrl?.hashCode ?? 0) ^
      status.hashCode ^
      createdAt.hashCode ^
      isSynced.hashCode;

  @override
  String toString() {
    return 'ChatMessage(id: $id, chatId: $chatId, senderId: $senderId, '
        'content: $content, type: $type, status: $status, '
        'createdAt: $createdAt, isSynced: $isSynced)';
  }
}
