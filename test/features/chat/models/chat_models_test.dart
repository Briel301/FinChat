import 'package:flutter_test/flutter_test.dart';
import 'package:finchat/features/chat/models/chat_message.dart';
import 'package:finchat/features/chat/models/conversation_summary.dart';

void main() {
  group('ChatMessage Domain Model Tests', () {
    final testDate = DateTime.utc(2026, 10, 11, 7, 30, 0);

    test('Instanciación inmutable completa y cálculo de isMine', () {
      final message = ChatMessage(
        id: 'c129e92a-3ef7-47bc-bb1d-4402a7bb8482',
        chatId: 'chat_uuid_01',
        senderId: 'user_uuid_100',
        content: 'Transferencia completada con éxito',
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: testDate,
        isSynced: true,
      );

      expect(message.id, 'c129e92a-3ef7-47bc-bb1d-4402a7bb8482');
      expect(message.isMine('user_uuid_100'), isTrue);
      expect(message.isMine('user_uuid_200'), isFalse);
      expect(message.isSynced, isTrue);
      expect(message.text, 'Transferencia completada con éxito');
      expect(message.timestamp, testDate);
    });

    test('Optimistic UI: soporte para status sending y isSynced false', () {
      final optimisticMsg = ChatMessage(
        id: 'client-gen-uuid-1234',
        chatId: 'chat_uuid_01',
        senderId: 'user_me',
        content: 'Enviando mensaje optimista...',
        type: MessageType.text,
        status: MessageStatus.sending,
        createdAt: testDate,
        isSynced: false,
      );

      expect(optimisticMsg.status, MessageStatus.sending);
      expect(optimisticMsg.isSynced, isFalse);

      final confirmedMsg = optimisticMsg.copyWith(
        status: MessageStatus.sent,
        isSynced: true,
      );

      expect(confirmedMsg.status, MessageStatus.sent);
      expect(confirmedMsg.isSynced, isTrue);
      expect(confirmedMsg.id, optimisticMsg.id);
    });

    test('toMap y fromMap con campos estándar de Supabase PostgREST', () {
      final original = ChatMessage(
        id: 'msg-uuid-999',
        chatId: 'chat-uuid-111',
        senderId: 'sender-uuid-222',
        content: 'Foto del comprobante',
        type: MessageType.image,
        mediaUrl: 'https://supabase.co/storage/v1/object/public/chat_images/recibo.webp',
        status: MessageStatus.delivered,
        createdAt: testDate,
        isSynced: true,
        fileSizeBytes: 20480,
      );

      final map = original.toMap();
      expect(map['id'], 'msg-uuid-999');
      expect(map['chat_id'], 'chat-uuid-111');
      expect(map['sender_id'], 'sender-uuid-222');
      expect(map['content'], 'Foto del comprobante');
      expect(map['message_type'], 'image');
      expect(map['media_url'], contains('recibo.webp'));
      expect(map['status'], 'delivered');
      expect(map['created_at'], testDate.toIso8601String());
      expect(map['is_synced'], isTrue);

      final deserialized = ChatMessage.fromMap(map);
      expect(deserialized, equals(original));
      expect(deserialized.type, MessageType.image);
      expect(deserialized.status, MessageStatus.delivered);
    });

    test('Tolerancia en fromMap a nombres alternativos y valores nulos', () {
      final looseMap = {
        'id': 'msg-loose-1',
        'chatId': 'chat-loose-1',
        'senderId': 'sender-loose-1',
        'text': 'Mensaje con clave text',
        'type': 'video',
        'status': 'read',
        'timestamp': '2026-10-11T08:00:00.000Z',
      };

      final message = ChatMessage.fromMap(looseMap);
      expect(message.id, 'msg-loose-1');
      expect(message.chatId, 'chat-loose-1');
      expect(message.senderId, 'sender-loose-1');
      expect(message.content, 'Mensaje con clave text');
      expect(message.type, MessageType.video);
      expect(message.status, MessageStatus.read);
      expect(message.createdAt.year, 2026);
    });
  });

  group('ConversationSummary Domain Model Tests', () {
    final testDate = DateTime.utc(2026, 10, 11, 7, 45, 0);

    test('Instanciación inmutable y serialización / deserialización', () {
      final summary = ConversationSummary(
        chatId: 'chat-uuid-abc',
        otherUserId: 'user-uuid-xyz',
        otherUsername: 'fin_advisor',
        otherFullName: 'Asesor Financiero',
        otherAvatarUrl: 'https://cdn.finchat.com/avatars/advisor.png',
        lastMessageContent: 'Tu saldo actual ha sido actualizado',
        lastMessageTime: testDate,
        unreadCount: 3,
      );

      expect(summary.chatId, 'chat-uuid-abc');
      expect(summary.unreadCount, 3);
      expect(summary.otherFullName, 'Asesor Financiero');

      final map = summary.toMap();
      expect(map['chat_id'], 'chat-uuid-abc');
      expect(map['other_user_id'], 'user-uuid-xyz');
      expect(map['last_message_content'], 'Tu saldo actual ha sido actualizado');
      expect(map['unread_count'], 3);

      final deserialized = ConversationSummary.fromMap(map);
      expect(deserialized, equals(summary));
    });

    test('copyWith preserva valores no alterados', () {
      final summary = ConversationSummary(
        chatId: 'chat-uuid-abc',
        otherUserId: 'user-uuid-xyz',
        otherUsername: 'fin_advisor',
        lastMessageContent: 'Hola',
        lastMessageTime: testDate,
        unreadCount: 1,
      );

      final updated = summary.copyWith(
        unreadCount: 0,
        lastMessageContent: 'Leído',
      );

      expect(updated.unreadCount, 0);
      expect(updated.lastMessageContent, 'Leído');
      expect(updated.otherUsername, 'fin_advisor');
      expect(updated.chatId, 'chat-uuid-abc');
    });
  });
}
