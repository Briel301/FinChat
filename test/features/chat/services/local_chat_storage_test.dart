import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finchat/features/chat/models/chat_message.dart';
import 'package:finchat/features/chat/models/conversation_summary.dart';
import 'package:finchat/features/chat/services/local_chat_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalChatStorage Unit Tests', () {
    late LocalChatStorage storage;
    final now = DateTime.utc(2026, 10, 11, 12, 0, 0);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storage = LocalChatStorage.withPreferences(prefs);
      LocalChatStorage.resetInstance(storage);
    });

    test('1. saveMessages y getCachedMessages: ciclo completo con orden cronológico', () async {
      const chatId = 'chat_001';
      final msg1 = ChatMessage(
        id: 'msg_1',
        chatId: chatId,
        senderId: 'user_a',
        content: 'Primer mensaje',
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: now.subtract(const Duration(minutes: 5)),
        isSynced: true,
      );
      final msg2 = ChatMessage(
        id: 'msg_2',
        chatId: chatId,
        senderId: 'user_b',
        content: 'Segundo mensaje',
        type: MessageType.text,
        status: MessageStatus.read,
        createdAt: now,
        isSynced: true,
      );

      // Guardar desordenados intencionalmente para validar ordenamiento cronológico
      await storage.saveMessages(chatId, [msg2, msg1]);

      // Lectura asincrónica
      final retrieved = await storage.getCachedMessages(chatId);
      expect(retrieved.length, 2);
      expect(retrieved[0].id, 'msg_1');
      expect(retrieved[0].content, 'Primer mensaje');
      expect(retrieved[1].id, 'msg_2');
      expect(retrieved[1].content, 'Segundo mensaje');

      // Lectura sincrónica instantánea (0 ms) desde L1
      final syncRetrieved = storage.getCachedMessagesSync(chatId);
      expect(syncRetrieved.length, 2);
      expect(syncRetrieved[0].id, 'msg_1');
    });

    test('2. getCachedMessages en chat inexistente retorna lista vacía inmediatamente', () async {
      final emptyResult = await storage.getCachedMessages('chat_inexistente');
      expect(emptyResult, isEmpty);

      final syncResult = storage.getCachedMessagesSync('chat_inexistente');
      expect(syncResult, isEmpty);

      // Verificación con chatId vacío
      final emptyIdResult = await storage.getCachedMessages('');
      expect(emptyIdResult, isEmpty);
    });

    test('3. upsertLocalMessage: inserta nuevo mensaje y actualiza estado existente', () async {
      const chatId = 'chat_002';
      final initialMsg = ChatMessage(
        id: 'msg_opt_01',
        chatId: chatId,
        senderId: 'user_me',
        content: 'Enviando comprobante...',
        type: MessageType.text,
        status: MessageStatus.sending,
        createdAt: now,
        isSynced: false,
      );

      // 1. Inserción de nuevo mensaje
      await storage.upsertLocalMessage(initialMsg);

      var cached = await storage.getCachedMessages(chatId);
      expect(cached.length, 1);
      expect(cached.first.status, MessageStatus.sending);
      expect(cached.first.isSynced, isFalse);

      // 2. Actualización de estado (sending -> sent, isSynced: true)
      final confirmedMsg = initialMsg.copyWith(
        status: MessageStatus.sent,
        isSynced: true,
      );
      await storage.upsertLocalMessage(confirmedMsg);

      cached = await storage.getCachedMessages(chatId);
      expect(cached.length, 1);
      expect(cached.first.id, 'msg_opt_01');
      expect(cached.first.status, MessageStatus.sent);
      expect(cached.first.isSynced, isTrue);

      // 3. Inserción de un segundo mensaje posterior
      final secondMsg = ChatMessage(
        id: 'msg_opt_02',
        chatId: chatId,
        senderId: 'user_peer',
        content: 'Comprobante recibido',
        type: MessageType.text,
        status: MessageStatus.read,
        createdAt: now.add(const Duration(seconds: 30)),
        isSynced: true,
      );
      await storage.upsertLocalMessage(secondMsg);

      cached = await storage.getCachedMessages(chatId);
      expect(cached.length, 2);
      expect(cached.last.id, 'msg_opt_02');
      expect(cached.last.content, 'Comprobante recibido');
    });

    test('4. saveConversations y getCachedConversations: persistencia de bandeja de entrada', () async {
      final conv1 = ConversationSummary(
        chatId: 'chat_c1',
        otherUserId: 'usr_c1',
        otherUsername: 'fin_advisor',
        otherFullName: 'Asesor Financiero',
        lastMessageContent: 'Reporte listo',
        lastMessageTime: now.subtract(const Duration(hours: 1)),
        unreadCount: 1,
      );
      final conv2 = ConversationSummary(
        chatId: 'chat_c2',
        otherUserId: 'usr_c2',
        otherUsername: 'soporte_finchat',
        otherFullName: 'Soporte',
        lastMessageContent: 'Bienvenido',
        lastMessageTime: now,
        unreadCount: 0,
      );

      await storage.saveConversations([conv1, conv2]);

      final cached = await storage.getCachedConversations();
      expect(cached.length, 2);
      // Debe estar ordenado por lastMessageTime descendente (más reciente primero)
      expect(cached[0].chatId, 'chat_c2');
      expect(cached[1].chatId, 'chat_c1');

      // Lectura sincrónica (0 ms)
      final syncCached = storage.getCachedConversationsSync();
      expect(syncCached.length, 2);
      expect(syncCached.first.chatId, 'chat_c2');
    });

    test('5. Manejo defensivo: tolera JSON corrupto sin provocar excepciones', () async {
      const chatId = 'chat_corrupto';
      final prefs = await SharedPreferences.getInstance();

      // Inyectar datos malformados en disco para mensajes
      await prefs.setString('${LocalChatStorage.keyMessagesPrefix}$chatId', '{esto_no_es_un_json_valido}');

      // Debe capturar FormatException y retornar lista vacía limpiamente
      final messages = await storage.getCachedMessages(chatId);
      expect(messages, isEmpty);

      // Inyectar JSON que no es una lista
      await prefs.setString('${LocalChatStorage.keyMessagesPrefix}$chatId', '{"campo": 123}');
      final messagesObj = await storage.getCachedMessages(chatId);
      expect(messagesObj, isEmpty);

      // Inyectar JSON corrupto para conversaciones
      await prefs.setString(LocalChatStorage.keyConversations, 'CORRUPT_JSON_DATA');
      final conversations = await storage.getCachedConversations();
      expect(conversations, isEmpty);
    });

    test('6. clearChatCache elimina el chat específico de memoria y disco', () async {
      const chatId = 'chat_to_delete';
      final msg = ChatMessage(
        id: 'msg_del',
        chatId: chatId,
        senderId: 'user_x',
        content: 'Mensaje temporal',
        createdAt: now,
      );

      await storage.saveMessages(chatId, [msg]);
      expect((await storage.getCachedMessages(chatId)).length, 1);

      await storage.clearChatCache(chatId);

      expect(await storage.getCachedMessages(chatId), isEmpty);
      expect(storage.getCachedMessagesSync(chatId), isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('${LocalChatStorage.keyMessagesPrefix}$chatId'), isNull);
    });

    test('7. purgeOldMessages recorta mensajes excedentes reteniendo los más recientes', () async {
      const chatId = 'chat_large';
      final messages = List.generate(
        15,
        (i) => ChatMessage(
          id: 'msg_$i',
          chatId: chatId,
          senderId: 'user_x',
          content: 'Mensaje #$i',
          createdAt: now.add(Duration(minutes: i)),
        ),
      );

      await storage.saveMessages(chatId, messages);
      expect((await storage.getCachedMessages(chatId)).length, 15);

      // Purgar manteniendo solo los 5 más recientes
      final purged = await storage.purgeOldMessages(chatId: chatId, maxMessages: 5);
      expect(purged, 10);

      final remaining = await storage.getCachedMessages(chatId);
      expect(remaining.length, 5);
      expect(remaining.first.id, 'msg_10');
      expect(remaining.last.id, 'msg_14');
    });

    test('8. enforceStorageQuota aplica política de cuota y LRU en múltiples chats', () async {
      final prefs = await SharedPreferences.getInstance();

      // Crear 4 chats con 10 mensajes cada uno
      for (int c = 1; c <= 4; c++) {
        final chatId = 'chat_quota_$c';
        final messages = List.generate(
          10,
          (i) => ChatMessage(
            id: 'msg_${c}_$i',
            chatId: chatId,
            senderId: 'user_x',
            content: 'Contenido $i',
            createdAt: now.add(Duration(minutes: i)),
          ),
        );
        await storage.saveMessages(chatId, messages);
      }

      // Modificar timestamps simulando acceso LRU
      await prefs.setInt('${LocalChatStorage.keyLastAccessedPrefix}chat_quota_1', 100);
      await prefs.setInt('${LocalChatStorage.keyLastAccessedPrefix}chat_quota_2', 200);
      await prefs.setInt('${LocalChatStorage.keyLastAccessedPrefix}chat_quota_3', 300);
      await prefs.setInt('${LocalChatStorage.keyLastAccessedPrefix}chat_quota_4', 400);

      // Aplicar cuota: máximo 3 mensajes por chat, máximo 2 chats en total
      final totalPurged = await storage.enforceStorageQuota(
        maxMessagesPerChat: 3,
        maxTotalChats: 2,
      );

      expect(totalPurged, greaterThan(0));

      // Los 2 chats más antiguos (chat_quota_1 y chat_quota_2) debieron ser eliminados por LRU
      expect(await storage.getCachedMessages('chat_quota_1'), isEmpty);
      expect(await storage.getCachedMessages('chat_quota_2'), isEmpty);

      // Los 2 chats más recientes deben conservar sus 3 mensajes más nuevos
      final remaining3 = await storage.getCachedMessages('chat_quota_3');
      final remaining4 = await storage.getCachedMessages('chat_quota_4');
      expect(remaining3.length, 3);
      expect(remaining4.length, 3);
    });

    test('9. clearAllCache limpia integralmente todos los datos de FinChat', () async {
      await storage.saveMessages('chat_a', [
        ChatMessage(id: 'a1', chatId: 'chat_a', senderId: 'u', content: 'A', createdAt: now),
      ]);
      await storage.saveConversations([
        ConversationSummary(
          chatId: 'chat_a',
          otherUserId: 'u',
          otherUsername: 'user_a',
          lastMessageContent: 'A',
          lastMessageTime: now,
        ),
      ]);

      expect((await storage.getCachedMessages('chat_a')).length, 1);
      expect((await storage.getCachedConversations()).length, 1);

      await storage.clearAllCache();

      expect(await storage.getCachedMessages('chat_a'), isEmpty);
      expect(await storage.getCachedConversations(), isEmpty);
    });
  });
}
