import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:finchat/core/network/connectivity_service.dart';
import 'package:finchat/features/chat/models/chat_message.dart';
import 'package:finchat/features/chat/models/conversation_summary.dart';
import 'package:finchat/features/chat/providers/chat_provider.dart';
import 'package:finchat/features/chat/services/chat_service.dart';
import 'package:finchat/features/chat/services/local_chat_storage.dart';
import 'package:finchat/features/chat/services/sync_queue_service.dart';
import 'package:finchat/features/chat/services/chat_sync_coordinator.dart';

class FakeConnectivity implements Connectivity {
  final StreamController<List<ConnectivityResult>> controller =
      StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> current = [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;
}

/// Mock interactivo de ChatService para pruebas unitarias de ChatProvider.
class MockChatService extends ChatService {
  MockChatService() : super.test();

  bool shouldFailSending = false;
  final List<ChatMessage> sentMessagesHistory = [];
  void Function(ChatMessage)? subscribedCallback;
  String? lastSubscribedChatId;
  String? lastUnsubscribedChatId;

  @override
  Future<List<ConversationSummary>> loadConversations() async {
    return [
      ConversationSummary(
        chatId: 'chat_test_01',
        otherUserId: 'usr_peer_01',
        otherUsername: 'peer_user',
        otherFullName: 'Peer Test',
        lastMessageContent: 'Último mensaje recibido',
        lastMessageTime: DateTime.utc(2026, 10, 11, 7, 0, 0),
        unreadCount: 2,
      ),
    ];
  }

  @override
  Future<List<ChatMessage>> loadChatHistory(String chatId) async {
    return [
      ChatMessage(
        id: 'msg_hist_01',
        chatId: chatId,
        senderId: 'usr_peer_01',
        content: 'Hola desde el historial',
        type: MessageType.text,
        status: MessageStatus.read,
        createdAt: DateTime.utc(2026, 10, 11, 6, 0, 0),
        isSynced: true,
      ),
    ];
  }

  @override
  Future<ChatMessage> sendMessage(ChatMessage message) async {
    sentMessagesHistory.add(message);
    if (shouldFailSending) {
      throw Exception('Fallo de red simulado');
    }
    return message.copyWith(status: MessageStatus.sent, isSynced: true);
  }

  @override
  void subscribeToChat(
    String chatId, {
    required void Function(ChatMessage message) onNewMessage,
  }) {
    lastSubscribedChatId = chatId;
    subscribedCallback = onNewMessage;
  }

  @override
  void unsubscribeFromChat(String chatId) {
    lastUnsubscribedChatId = chatId;
    subscribedCallback = null;
  }
}

void main() {
  group('ChatProvider Unit Tests', () {
    late MockChatService mockService;
    late ChatProvider provider;
    const testUserId = 'usr_me_123';

    setUp(() {
      mockService = MockChatService();
      provider = ChatProvider(
        chatService: mockService,
        currentUserId: testUserId,
      );
    });

    test('1. loadConversations actualiza estado y notifica oyentes', () async {
      int notifications = 0;
      provider.addListener(() => notifications++);

      expect(provider.conversations, isEmpty);
      expect(provider.isLoadingConversations, isFalse);

      final future = provider.loadConversations();
      expect(provider.isLoadingConversations, isTrue);

      await future;
      expect(provider.isLoadingConversations, isFalse);
      expect(provider.conversations.length, 1);
      expect(provider.conversations.first.otherUsername, 'peer_user');
      expect(notifications, greaterThanOrEqualTo(2));
    });

    test('2. enterChat carga historial y activa suscripción WebSocket', () async {
      int notifications = 0;
      provider.addListener(() => notifications++);

      await provider.enterChat('chat_test_01');

      expect(provider.activeChatId, 'chat_test_01');
      expect(provider.isLoadingHistory, isFalse);
      expect(provider.currentMessages.length, 1);
      expect(provider.currentMessages.first.content, 'Hola desde el historial');
      expect(mockService.lastSubscribedChatId, 'chat_test_01');
      expect(mockService.subscribedCallback, isNotNull);
      expect(notifications, greaterThanOrEqualTo(2));
    });

    test('3. leaveChat cancela suscripción y limpia sala activa', () async {
      await provider.enterChat('chat_test_01');
      expect(provider.activeChatId, 'chat_test_01');

      provider.leaveChat();

      expect(provider.activeChatId, isNull);
      expect(provider.currentMessages, isEmpty);
      expect(mockService.lastUnsubscribedChatId, 'chat_test_01');
      expect(mockService.subscribedCallback, isNull);
    });

    test('4. sendTextMessage ejecuta Optimistic UI instantáneo y confirma éxito', () async {
      await provider.enterChat('chat_test_01');
      await provider.loadConversations();

      final statesDuringSend = <MessageStatus>[];
      provider.addListener(() {
        if (provider.currentMessages.length > 1) {
          statesDuringSend.add(provider.currentMessages.last.status);
        }
      });

      final sendFuture = provider.sendTextMessage('Pago por transferencia enviado');

      // VERIFICACIÓN OPTIMISTA INMEDIATA (antes de que complete el await si hubiera latencia)
      expect(provider.currentMessages.length, 2);
      final optimisticMsg = provider.currentMessages.last;
      expect(optimisticMsg.content, 'Pago por transferencia enviado');
      expect(optimisticMsg.status, MessageStatus.sending);
      expect(optimisticMsg.isSynced, isFalse);
      expect(optimisticMsg.senderId, testUserId);
      expect(optimisticMsg.id, isNotEmpty);

      // Conversación resumen actualizada optimistamente
      expect(provider.conversations.first.lastMessageContent, 'Pago por transferencia enviado');

      // Esperar resolución
      await sendFuture;

      // Estado confirmado por backend
      final confirmedMsg = provider.currentMessages.last;
      expect(confirmedMsg.status, MessageStatus.sent);
      expect(confirmedMsg.isSynced, isTrue);
      expect(confirmedMsg.id, optimisticMsg.id); // Mismo ID cliente UUIDv4
      expect(statesDuringSend, contains(MessageStatus.sending));
      expect(statesDuringSend, contains(MessageStatus.sent));
    });

    test('5. sendTextMessage marca estado failed en caso de error de red', () async {
      mockService.shouldFailSending = true;
      await provider.enterChat('chat_test_01');

      await provider.sendTextMessage('Mensaje que fallará');

      expect(provider.currentMessages.length, 2);
      final failedMsg = provider.currentMessages.last;
      expect(failedMsg.content, 'Mensaje que fallará');
      expect(failedMsg.status, MessageStatus.failed);
      expect(failedMsg.isSynced, isFalse);
      expect(provider.errorMessage, contains('Fallo de red simulado'));
    });

    test('6. Recepción en tiempo real vía WebSocket inserta mensajes sin duplicar', () async {
      await provider.enterChat('chat_test_01');
      expect(provider.currentMessages.length, 1);

      // Simular llegada de mensaje externo vía WebSocket
      final externalMsg = ChatMessage(
        id: 'ws_msg_incoming_999',
        chatId: 'chat_test_01',
        senderId: 'usr_peer_01',
        content: 'Mensaje entrante vía WebSocket',
        type: MessageType.text,
        status: MessageStatus.delivered,
        createdAt: DateTime.utc(2026, 10, 11, 7, 30, 0),
        isSynced: true,
      );

      mockService.subscribedCallback?.call(externalMsg);

      expect(provider.currentMessages.length, 2);
      expect(provider.currentMessages.last.id, 'ws_msg_incoming_999');
      expect(provider.currentMessages.last.content, 'Mensaje entrante vía WebSocket');

      // Si llega de nuevo el mismo mensaje (ej. actualización de lectura), no debe duplicar
      final readReceipt = externalMsg.copyWith(status: MessageStatus.read);
      mockService.subscribedCallback?.call(readReceipt);

      expect(provider.currentMessages.length, 2);
      expect(provider.currentMessages.last.status, MessageStatus.read);
    });

    test('7. retryMessage reintenta el envío de mensaje en estado failed', () async {
      mockService.shouldFailSending = true;
      await provider.enterChat('chat_test_01');
      await provider.sendTextMessage('Mensaje fallido');

      final failedId = provider.currentMessages.last.id;
      expect(provider.currentMessages.last.status, MessageStatus.failed);

      // Ahora restauramos la conexión y reintentamos
      mockService.shouldFailSending = false;
      await provider.retryMessage(failedId);

      expect(provider.currentMessages.last.status, MessageStatus.sent);
      expect(provider.currentMessages.last.isSynced, isTrue);
    });

    test('8. loadConversations aplica Cache-First: lee inmediatamente de LocalChatStorage', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final customStorage = LocalChatStorage(preferences: prefs);
      final now = DateTime.utc(2026, 10, 11, 8, 0, 0);

      await customStorage.saveConversations([
        ConversationSummary(
          chatId: 'cached_chat_1',
          otherUserId: 'usr_c1',
          otherUsername: 'usuario_cache',
          lastMessageContent: 'Mensaje desde caché local',
          lastMessageTime: now,
        ),
      ]);

      final customProvider = ChatProvider(
        chatService: mockService,
        localChatStorage: customStorage,
        currentUserId: testUserId,
      );

      await customProvider.loadConversations();

      expect(customProvider.conversations.isNotEmpty, isTrue);
    });

    test('9. enterChat carga historial desde LocalChatStorage de inmediato en modo offline', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final customStorage = LocalChatStorage(preferences: prefs);
      final now = DateTime.utc(2026, 10, 11, 8, 0, 0);

      const chatId = 'offline_room_1';
      await customStorage.saveMessages(chatId, [
        ChatMessage(
          id: 'msg_cached_1',
          chatId: chatId,
          senderId: 'usr_other',
          content: 'Historial local offline',
          createdAt: now,
        ),
      ]);

      final fakeConn = FakeConnectivity()..current = [ConnectivityResult.none];
      final offlineConnService = ConnectivityService.withDependencies(
        connectivity: fakeConn,
        probe: () async => false,
      );
      await offlineConnService.initialize();

      final offlineProvider = ChatProvider(
        chatService: mockService,
        localChatStorage: customStorage,
        connectivityService: offlineConnService,
        currentUserId: testUserId,
      );

      await offlineProvider.enterChat(chatId);

      expect(offlineProvider.currentMessages.length, 1);
      expect(offlineProvider.currentMessages.first.content, 'Historial local offline');
    });

    test('10. sendTextMessage en modo offline encola en SyncQueueService sin arrojar error', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final customStorage = LocalChatStorage(preferences: prefs);
      final customQueue = SyncQueueService.withDependencies(
        preferences: prefs,
        localStorage: customStorage,
      );

      final fakeConn = FakeConnectivity()..current = [ConnectivityResult.none];
      final offlineConnService = ConnectivityService.withDependencies(
        connectivity: fakeConn,
        probe: () async => false,
      );
      await offlineConnService.initialize();

      final offlineProvider = ChatProvider(
        chatService: mockService,
        localChatStorage: customStorage,
        syncQueueService: customQueue,
        connectivityService: offlineConnService,
        currentUserId: testUserId,
      );

      await offlineProvider.enterChat('offline_chat_xyz');
      await offlineProvider.sendTextMessage('Mensaje enviado sin internet');

      expect(offlineProvider.errorMessage, isNull);
      expect(offlineProvider.currentMessages.length, 2);
      final pendingMsg = offlineProvider.currentMessages.last;
      expect(pendingMsg.content, 'Mensaje enviado sin internet');
      expect(pendingMsg.status, MessageStatus.sending);
      expect(pendingMsg.isSynced, isFalse);

      // Verificación en la cola Outbox
      expect(customQueue.pendingCount, 1);
    });

    test('11. ChatSyncCoordinator notifica éxito y ChatProvider actualiza mensaje a sent', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final customStorage = LocalChatStorage(preferences: prefs);
      final customQueue = SyncQueueService.withDependencies(
        preferences: prefs,
        localStorage: customStorage,
      );

      final fakeConn = FakeConnectivity();
      final connService = ConnectivityService.withDependencies(
        connectivity: fakeConn,
        probe: () async => true,
      );

      final coordinator = ChatSyncCoordinator(
        connectivityService: connService,
        syncQueueService: customQueue,
        localStorage: customStorage,
        chatService: mockService,
        autoStart: false,
      );

      final reactiveProvider = ChatProvider(
        chatService: mockService,
        localChatStorage: customStorage,
        syncQueueService: customQueue,
        connectivityService: connService,
        syncCoordinator: coordinator,
        currentUserId: testUserId,
      );

      await reactiveProvider.enterChat('chat_coord_01');

      // Desconectar para enviar en modo offline
      connService.toggleOfflineSimulation(true);

      await reactiveProvider.sendTextMessage('Esperando despacho del coordinador');
      final sendingMsg = reactiveProvider.currentMessages.last;
      expect(sendingMsg.status, MessageStatus.sending);
      expect(sendingMsg.isSynced, isFalse);

      // Reconectar y procesar la cola
      connService.toggleOfflineSimulation(false);
      await coordinator.processQueue();
      await Future<void>.delayed(Duration.zero);

      final updatedMsg = reactiveProvider.currentMessages.last;
      expect(updatedMsg.id, sendingMsg.id);
      expect(updatedMsg.status, MessageStatus.sent);
      expect(updatedMsg.isSynced, isTrue);

      coordinator.dispose();
      reactiveProvider.dispose();
    });
  });
}
