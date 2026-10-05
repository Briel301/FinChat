enum MessageType { text, image, video, audio }

enum MessageDeliveryStatus { pending, sent, delivered, read }

/// Entidad inmutable que representa un mensaje individual dentro de un chat 1 a 1.
class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String senderUsername;
  final String text;
  final MessageType type;
  final MessageDeliveryStatus status;
  final DateTime timestamp;
  final bool isFromMe;
  final bool isSynced; // Soporte Offline (false = guardado localmente, pendiente de sync)

  // Metadatos multimedia (Must Have: fotos, videos, audio de máx 1 min)
  final String? mediaUrl;
  final int? fileSizeBytes;
  final int? durationSeconds; // Para notas de voz (máx 60 segundos)

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderUsername,
    required this.text,
    this.type = MessageType.text,
    this.status = MessageDeliveryStatus.delivered,
    required this.timestamp,
    required this.isFromMe,
    this.isSynced = true,
    this.mediaUrl,
    this.fileSizeBytes,
    this.durationSeconds,
  });

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? senderUsername,
    String? text,
    MessageType? type,
    MessageDeliveryStatus? status,
    DateTime? timestamp,
    bool? isFromMe,
    bool? isSynced,
    String? mediaUrl,
    int? fileSizeBytes,
    int? durationSeconds,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      senderUsername: senderUsername ?? this.senderUsername,
      text: text ?? this.text,
      type: type ?? this.type,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      isFromMe: isFromMe ?? this.isFromMe,
      isSynced: isSynced ?? this.isSynced,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chat_id': chatId,
      'sender_id': senderId,
      'sender_username': senderUsername,
      'text': text,
      'type': type.name,
      'status': status.name,
      'timestamp': timestamp.toIso8601String(),
      'media_url': mediaUrl,
      'file_size_bytes': fileSizeBytes,
      'duration_seconds': durationSeconds,
    };
  }
}
