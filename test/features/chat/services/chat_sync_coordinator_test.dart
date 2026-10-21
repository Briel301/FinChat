import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finchat/core/network/connectivity_service.dart';
import 'package:finchat/features/chat/models/chat_message.dart';
import 'package:finchat/features/chat/services/chat_service.dart';
import 'package:finchat/features/chat/services/chat_sync_coordinator.dart';
import 'package:finchat/features/chat/services/local_chat_storage.dart';
import 'package:finchat/features/chat/services/sync_queue_service.dart';

class FakeConnectivity implements Connectivity {
  final StreamController<List<ConnectivityResult>> controller =
      StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> current = [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;
}

class TestableChatService extends ChatService {
  TestableChatService({
    super.storage,
    super.syncQueue,
  }) : super.test();

  final List<ChatMessage> dispatchedMessages = [];
  bool shouldThrowOnMessageId(String id) => failIds.contains(id);
  final Set<String> failIds = {};
  Completer<void>? delayCompleter;

  @override
  Future<ChatMessage> sendMessage(ChatMessage message) async {
    if (delayCompleter != null) {
      await delayCompleter!.future;
    }
    if (shouldThrowOnMessageId(message.id)) {
      throw Exception('Fallo de red simulado para ${message.id}');
    }
    dispatchedMessages.add(message);
    return message.copyWith(status: MessageStatus.sent, isSynced: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatSyncCoordinator Unit Tests', () {
    late FakeConnectivity fakeConnectivity;
    late ConnectivityService connectivityService;
    late SharedPreferences prefs;
    late LocalChatStorage storage;
    late SyncQueueService queueService;
    late TestableChatService chatService;
    late ChatSyncCoordinator coordinator;

    final testDate = DateTime.utc(2026, 10, 11, 16, 0, 0);

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

      fakeConnectivity = FakeConnectivity();
      connectivityService = ConnectivityService.withDependencies(
        connectivity: fakeConnectivity,
        probe: () async => true,
      );
      await connectivityService.initialize();

      chatService = TestableChatService(
        storage: storage,
        syncQueue: queueService,
      );
    });

    tearDown(() {
      coordinator.dispose();
      connectivityService.dispose();
    });

    test('1. Inyección y enlace de servicios', () {
      coordinator = ChatSyncCoordinator(
        connectivityService: connectivityService,
        syncQueueService: queueService,
        localStorage: storage,
        chatService: chatService,
        autoStart: false,
      );

      expect(coordinator.connectivityService, connectivityService);
      expect(coordinator.syncQueueService, queueService);
      expect(coordinator.localStorage, storage);
      expect(coordinator.chatService, chatService);
      expect(coordinator.isSyncing, isFalse);
      expect(coordinator.retryCount, 0);
    });

    test('2. Disparo reactivo al transicionar de offline a online', () async {
      // Simular desconexión inicial
      connectivityService.toggleOfflineSimulation(true);
      expect(connectivityService.isOnline, isFalse);

      coordinator = ChatSyncCoordinator(
        connectivityService: connectivityService,
        syncQueueService: queueService,
        localStorage: storage,
        chatService: chatService,
        autoStart: true,
      );

      // Encolar mensaje estando offline
      await queueService.enqueueMessage(
        ChatMessage(id: 'offline_msg_1', chatId: 'c1', senderId: 'u', content: 'Msg 1', createdAt: testDate),
      );
      expect(queueService.pendingCount, 1);
      expect(chatService.dispatchedMessages, isEmpty);

      final completer = Completer<int>();
      coordinator.onSyncCompleted = (count) {
        if (!completer.isCompleted) completer.complete(count);
      };

      // Restablecer conexión: debe disparar automáticamente la sincronización
      connectivityService.toggleOfflineSimulation(false);

      final syncedCount = await completer.future.timeout(const Duration(seconds: 3));
      expect(syncedCount, 1);
      expect(queueService.pendingCount, 0);
      expect(chatService.dispatchedMessages.length, 1);
      expect(chatService.dispatchedMessages.first.id, 'offline_msg_1');
    });

    test('3. Procesamiento secuencial FIFO en estricto orden cronológico', () async {
      coordinator = ChatSyncCoordinator(
        connectivityService: connectivityService,
        syncQueueService: queueService,
        localStorage: storage,
        chatService: chatService,
        autoStart: false,
      );

      final m1 = ChatMessage(id: 'm1', chatId: 'c1', senderId: 'u', content: '1', createdAt: testDate);
      final m2 = ChatMessage(id: 'm2', chatId: 'c1', senderId: 'u', content: '2', createdAt: testDate.add(const Duration(seconds: 5)));
      final m3 = ChatMessage(id: 'm3', chatId: 'c1', senderId: 'u', content: '3', createdAt: testDate.add(const Duration(seconds: 10)));

      // Encolar deliberadamente desordenados
      await queueService.enqueueMessage(m3);
      await queueService.enqueueMessage(m1);
      await queueService.enqueueMessage(m2);

      final syncedCount = await coordinator.processQueue();

      expect(syncedCount, 3);
      expect(queueService.pendingCount, 0);
      expect(chatService.dispatchedMessages.length, 3);
      // El orden de despacho debe ser m1 -> m2 -> m3
      expect(chatService.dispatchedMessages[0].id, 'm1');
      expect(chatService.dispatchedMessages[1].id, 'm2');
      expect(chatService.dispatchedMessages[2].id, 'm3');
    });

    test('4. Prevención de concurrencia mediante bandera isSyncing', () async {
      chatService.delayCompleter = Completer<void>();

      coordinator = ChatSyncCoordinator(
        connectivityService: connectivityService,
        syncQueueService: queueService,
        localStorage: storage,
        chatService: chatService,
        autoStart: false,
      );

      await queueService.enqueueMessage(
        ChatMessage(id: 'm_lock', chatId: 'c1', senderId: 'u', content: 'Lock test', createdAt: testDate),
      );

      // Lanzar primera sincronización (se quedará pausada en delayCompleter)
      final future1 = coordinator.processQueue();
      expect(coordinator.isSyncing, isTrue);

      // Segunda llamada concurrente mientras future1 está en curso
      final secondSyncResult = await coordinator.processQueue();
      expect(secondSyncResult, 0); // Rechazado por isSyncing

      // Liberar future1
      chatService.delayCompleter!.complete();
      final firstSyncResult = await future1;

      expect(firstSyncResult, 1);
      expect(coordinator.isSyncing, isFalse);
    });

    test('5. Interrupción ordenada y preservación de cola ante fallo intermedio de red', () async {
      coordinator = ChatSyncCoordinator(
        connectivityService: connectivityService,
        syncQueueService: queueService,
        localStorage: storage,
        chatService: chatService,
        initialRetryDelay: const Duration(milliseconds: 50),
        autoStart: false,
      );

      final m1 = ChatMessage(id: 'ok_1', chatId: 'c', senderId: 'u', content: 'OK 1', createdAt: testDate);
      final m2 = ChatMessage(id: 'fail_2', chatId: 'c', senderId: 'u', content: 'FAIL 2', createdAt: testDate.add(const Duration(seconds: 2)));
      final m3 = ChatMessage(id: 'ok_3', chatId: 'c', senderId: 'u', content: 'OK 3', createdAt: testDate.add(const Duration(seconds: 4)));

      await queueService.enqueueMessage(m1);
      await queueService.enqueueMessage(m2);
      await queueService.enqueueMessage(m3);

      // Configurar fallo simulado para m2
      chatService.failIds.add('fail_2');

      String? caughtErrorId;
      coordinator.onSyncError = (msgId, error) {
        caughtErrorId = msgId;
      };

      final syncedCount = await coordinator.processQueue();

      // m1 debió ser despachado exitosamente
      expect(syncedCount, 1);
      expect(chatService.dispatchedMessages.length, 1);
      expect(chatService.dispatchedMessages.first.id, 'ok_1');

      // Error reportado para fail_2
      expect(caughtErrorId, 'fail_2');

      // fail_2 y ok_3 siguen intactos en la cola (no se intentó ok_3 para preservar FIFO)
      final remaining = await queueService.getPendingMessages();
      expect(remaining.length, 2);
      expect(remaining[0].id, 'fail_2');
      expect(remaining[1].id, 'ok_3');
      expect(coordinator.retryCount, 1);
    });

    test('6. Reintento programado con exponential backoff se ejecuta tras subsanar error', () async {
      coordinator = ChatSyncCoordinator(
        connectivityService: connectivityService,
        syncQueueService: queueService,
        localStorage: storage,
        chatService: chatService,
        initialRetryDelay: const Duration(milliseconds: 80),
        autoStart: false,
      );

      await queueService.enqueueMessage(
        ChatMessage(id: 'retry_msg', chatId: 'c', senderId: 'u', content: 'Retry', createdAt: testDate),
      );

      // Falla inicialmente
      chatService.failIds.add('retry_msg');
      await coordinator.processQueue();
      expect(coordinator.retryCount, 1);
      expect(queueService.pendingCount, 1);

      // Subsanar error de red
      chatService.failIds.remove('retry_msg');

      final retryCompleted = Completer<int>();
      coordinator.onSyncCompleted = (count) {
        if (!retryCompleted.isCompleted) retryCompleted.complete(count);
      };

      // Esperar a que el Timer de exponential backoff se dispare
      final synced = await retryCompleted.future.timeout(const Duration(seconds: 2));
      expect(synced, 1);
      expect(queueService.pendingCount, 0);
      expect(coordinator.retryCount, 0);
    });

    test('7. Streams reactivos emiten eventos correctamente', () async {
      coordinator = ChatSyncCoordinator(
        connectivityService: connectivityService,
        syncQueueService: queueService,
        localStorage: storage,
        chatService: chatService,
        autoStart: false,
      );

      final emittedMessages = <ChatMessage>[];
      final emittedCounts = <int>[];

      final sub1 = coordinator.onMessageSyncedStream.listen(emittedMessages.add);
      final sub2 = coordinator.onSyncCompletedStream.listen(emittedCounts.add);

      await queueService.enqueueMessage(
        ChatMessage(id: 'stream_1', chatId: 'c', senderId: 'u', content: 'S1', createdAt: testDate),
      );

      await coordinator.processQueue();
      await Future<void>.delayed(Duration.zero);

      expect(emittedMessages.length, 1);
      expect(emittedMessages.first.id, 'stream_1');
      expect(emittedCounts, [1]);

      await sub1.cancel();
      await sub2.cancel();
    });

    test('8. Limpieza adecuada en dispose sin memory leaks', () async {
      coordinator = ChatSyncCoordinator(
        connectivityService: connectivityService,
        syncQueueService: queueService,
        localStorage: storage,
        chatService: chatService,
        autoStart: false,
      );

      coordinator.dispose();

      // Llamadas posteriores deben ser no-op seguras
      final result = await coordinator.processQueue();
      expect(result, 0);
    });
  });
}
