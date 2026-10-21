import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finchat/features/chat/models/chat_message.dart';
import 'package:finchat/features/chat/services/local_chat_storage.dart';
import 'package:finchat/features/chat/services/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncQueueService Outbox Unit Tests', () {
    late SharedPreferences prefs;
    late LocalChatStorage storage;
    late SyncQueueService queueService;
    final testDate = DateTime.utc(2026, 10, 11, 14, 0, 0);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      storage = LocalChatStorage(preferences: prefs);
      LocalChatStorage.resetInstance(storage);

      queueService = SyncQueueService.withDependencies(
        preferences: prefs,
        localStorage: storage,
      );
      SyncQueueService.resetInstance(queueService);
    });

    test('1. enqueueMessage marca isSynced false, status sending y actualiza almacenamiento local', () async {
      final original = ChatMessage(
        id: 'msg_001',
        chatId: 'chat_alpha',
        senderId: 'usr_me',
        content: 'Transferencia realizada',
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: testDate,
        isSynced: true,
      );

      final queued = await queueService.enqueueMessage(original);

      // Verificación de estado del mensaje retornado
      expect(queued.id, 'msg_001');
      expect(queued.status, MessageStatus.sending);
      expect(queued.isSynced, isFalse);

      // Verificación en cola
      expect(queueService.pendingCount, 1);
      expect(queueService.pendingCountNotifier.value, 1);
      final pendingList = await queueService.getPendingMessages();
      expect(pendingList.length, 1);
      expect(pendingList.first.id, 'msg_001');

      // Verificación en LocalChatStorage (debe haberse guardado con status sending)
      final localMsgs = await storage.getCachedMessages('chat_alpha');
      expect(localMsgs.length, 1);
      expect(localMsgs.first.id, 'msg_001');
      expect(localMsgs.first.status, MessageStatus.sending);
      expect(localMsgs.first.isSynced, isFalse);
    });

    test('2. Tolerancia a reinicios de la aplicación (Persistencia Outbox en disco)', () async {
      final msg1 = ChatMessage(
        id: 'msg_persist_1',
        chatId: 'chat_beta',
        senderId: 'usr_me',
        content: 'Mensaje persistido 1',
        createdAt: testDate,
      );
      final msg2 = ChatMessage(
        id: 'msg_persist_2',
        chatId: 'chat_beta',
        senderId: 'usr_me',
        content: 'Mensaje persistido 2',
        createdAt: testDate.add(const Duration(seconds: 10)),
      );

      await queueService.enqueueMessage(msg1);
      await queueService.enqueueMessage(msg2);
      expect(queueService.pendingCount, 2);

      // Simular reinicio de la aplicación recreando el servicio con el mismo backend de disco
      final restoredQueueService = SyncQueueService.withDependencies(
        preferences: prefs,
        localStorage: storage,
      );
      await restoredQueueService.init();

      expect(restoredQueueService.pendingCount, 2);
      final pendingRestored = await restoredQueueService.getPendingMessages();
      expect(pendingRestored.length, 2);
      expect(pendingRestored[0].id, 'msg_persist_1');
      expect(pendingRestored[1].id, 'msg_persist_2');
    });

    test('3. Cero duplicación de mensajes encolados mediante control de UUIDs', () async {
      final msg = ChatMessage(
        id: 'duplicate_uuid_999',
        chatId: 'chat_gamma',
        senderId: 'usr_me',
        content: 'Contenido inicial',
        createdAt: testDate,
      );

      await queueService.enqueueMessage(msg);
      expect(queueService.pendingCount, 1);

      // Encolar nuevamente con el mismo UUID pero texto actualizado
      final updatedMsg = msg.copyWith(content: 'Contenido editado antes del despacho');
      await queueService.enqueueMessage(updatedMsg);

      expect(queueService.pendingCount, 1);
      final pending = await queueService.getPendingMessages();
      expect(pending.length, 1);
      expect(pending.first.id, 'duplicate_uuid_999');
      expect(pending.first.content, 'Contenido editado antes del despacho');
    });

    test('4. getPendingMessages retorna orden cronológico FIFO estricto (createdAt ASC)', () async {
      final msgEarly = ChatMessage(
        id: 'early_msg',
        chatId: 'chat_delta',
        senderId: 'usr_me',
        content: 'Primero en tiempo',
        createdAt: testDate.subtract(const Duration(minutes: 5)),
      );
      final msgLate = ChatMessage(
        id: 'late_msg',
        chatId: 'chat_delta',
        senderId: 'usr_me',
        content: 'Segundo en tiempo',
        createdAt: testDate,
      );

      // Encolar deliberadamente en orden invertido
      await queueService.enqueueMessage(msgLate);
      await queueService.enqueueMessage(msgEarly);

      final list = await queueService.getPendingMessages();
      expect(list.length, 2);
      expect(list[0].id, 'early_msg');
      expect(list[1].id, 'late_msg');
    });

    test('5. dequeueMessage retira mensaje de cola y actualiza contador reactivo', () async {
      final msg = ChatMessage(
        id: 'msg_to_dequeue',
        chatId: 'chat_eps',
        senderId: 'usr_me',
        content: 'Por retirar',
        createdAt: testDate,
      );

      await queueService.enqueueMessage(msg);
      expect(queueService.pendingCount, 1);

      final removed = await queueService.dequeueMessage('msg_to_dequeue');
      expect(removed, isNotNull);
      expect(removed!.id, 'msg_to_dequeue');
      expect(queueService.pendingCount, 0);

      // Intentar retirar mensaje que ya no existe
      final notFound = await queueService.dequeueMessage('inexistente');
      expect(notFound, isNull);
      expect(queueService.pendingCount, 0);
    });

    test('6. markAsSynced retira de la cola y actualiza LocalChatStorage a sent e isSynced true', () async {
      const chatId = 'chat_sync';
      final msg = ChatMessage(
        id: 'msg_sync_100',
        chatId: chatId,
        senderId: 'usr_me',
        content: 'Pago de nómina confirmado',
        createdAt: testDate,
      );

      await queueService.enqueueMessage(msg);

      // Confirmar sincronización con Supabase
      final synced = await queueService.markAsSynced('msg_sync_100');
      expect(synced, isNotNull);
      expect(synced!.status, MessageStatus.sent);
      expect(synced.isSynced, isTrue);

      // Ya no debe estar en cola
      expect(queueService.pendingCount, 0);
      expect(queueService.containsMessage('msg_sync_100'), isFalse);

      // Debe estar actualizado en LocalChatStorage
      final localMsgs = await storage.getCachedMessages(chatId);
      expect(localMsgs.length, 1);
      expect(localMsgs.first.id, 'msg_sync_100');
      expect(localMsgs.first.status, MessageStatus.sent);
      expect(localMsgs.first.isSynced, isTrue);
    });

    test('7. Contador reactivo pendingCountNotifier notifica transiciones a observadores UI', () async {
      final countHistory = <int>[];
      queueService.pendingCountNotifier.addListener(() {
        countHistory.add(queueService.pendingCount);
      });

      final msg1 = ChatMessage(id: 'm1', chatId: 'c', senderId: 'u', content: '1', createdAt: testDate);
      final msg2 = ChatMessage(id: 'm2', chatId: 'c', senderId: 'u', content: '2', createdAt: testDate);

      await queueService.enqueueMessage(msg1);
      await queueService.enqueueMessage(msg2);
      await queueService.markAsSynced('m1');
      await queueService.clearQueue();

      expect(countHistory, containsAllInOrder([1, 2, 1, 0]));
      expect(queueService.pendingCount, 0);
    });

    test('8. Manejo defensivo ante JSON corrupto en cola outbox', () async {
      await prefs.setString(SyncQueueService.keySyncQueue, '{formato_invalido}');

      final brokenService = SyncQueueService.withDependencies(
        preferences: prefs,
        localStorage: storage,
      );
      await brokenService.init();

      expect(brokenService.pendingCount, 0);
      expect(await brokenService.getPendingMessages(), isEmpty);
    });

    test('9. clearQueue vacía memoria y disco completamente', () async {
      await queueService.enqueueMessage(
        ChatMessage(id: 'clr1', chatId: 'c', senderId: 'u', content: 'c', createdAt: testDate),
      );
      expect(queueService.pendingCount, 1);

      await queueService.clearQueue();
      expect(queueService.pendingCount, 0);
      expect(prefs.getString(SyncQueueService.keySyncQueue), isNull);
    });
  });
}
