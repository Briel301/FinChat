import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finchat/core/network/connectivity_service.dart';
import 'package:finchat/features/chat/models/chat_message.dart';
import 'package:finchat/features/chat/services/chat_service.dart';
import 'package:finchat/features/chat/services/chat_sync_coordinator.dart';
import 'package:finchat/features/chat/services/local_chat_storage.dart';
import 'package:finchat/features/chat/services/sync_queue_service.dart';
import 'package:finchat/features/notifications/services/notification_service.dart';
import 'package:finchat/features/ui_showcase/views/offline_sync_view.dart';

class MockChatServiceForSyncView extends ChatService {
  MockChatServiceForSyncView() : super.test();

  int processedCount = 0;

  @override
  Future<ChatMessage> sendMessage(ChatMessage message) async {
    processedCount++;
    return message.copyWith(status: MessageStatus.sent, isSynced: true);
  }
}

void main() {
  late ConnectivityService connectivityService;
  late SyncQueueService syncQueueService;
  late LocalChatStorage localChatStorage;
  late MockChatServiceForSyncView mockChatService;
  late ChatSyncCoordinator syncCoordinator;
  late NotificationService notificationService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    connectivityService = ConnectivityService();
    connectivityService.toggleOfflineSimulation(false);

    syncQueueService = SyncQueueService.instance;
    await syncQueueService.clearQueue();
    localChatStorage = LocalChatStorage.instance;
    mockChatService = MockChatServiceForSyncView();

    syncCoordinator = ChatSyncCoordinator(
      connectivityService: connectivityService,
      syncQueueService: syncQueueService,
      localStorage: localChatStorage,
      chatService: mockChatService,
    );

    notificationService = NotificationService();
    notificationService.clearNotification();
  });

  tearDown(() {
    syncCoordinator.dispose();
  });

  Widget buildTestableSyncView() {
    return MaterialApp(
      home: OfflineSyncView(
        connectivityService: connectivityService,
        syncQueueService: syncQueueService,
        syncCoordinator: syncCoordinator,
        localChatStorage: localChatStorage,
        notificationService: notificationService,
      ),
    );
  }

  testWidgets('1. Renderiza elementos principales: MoSCoW, KPIs y Bitácora', (tester) async {
    await tester.pumpWidget(buildTestableSyncView());
    await tester.pumpAndSettle();

    expect(find.text('Simulador & Monitor Offline'), findsOneWidget);
    expect(find.textContaining('Should Have (15 pts totales)'), findsOneWidget);
    expect(find.text('En línea'), findsOneWidget);
    expect(find.text('Pending Outbox'), findsOneWidget);
    expect(find.text('Encolar Mensaje'), findsOneWidget);
    expect(find.text('Forzar Sincro'), findsOneWidget);
    expect(find.text('Bitácora de Sincronización en Vivo:'), findsOneWidget);
  });

  testWidgets('2. Switch de simulación de desconexión alterna estado de red', (tester) async {
    await tester.pumpWidget(buildTestableSyncView());
    await tester.pumpAndSettle();

    expect(find.text('En línea'), findsOneWidget);
    expect(connectivityService.isOnline, isTrue);

    // Tocar el interruptor
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(connectivityService.isSimulatedOffline, isTrue);
    expect(find.text('Fuera de línea'), findsOneWidget);
    expect(find.text('Red Desconectada'), findsOneWidget);
  });

  testWidgets('3. Encolar mensaje agrega item a la cola y actualiza el contador', (tester) async {
    await tester.pumpWidget(buildTestableSyncView());
    await tester.pumpAndSettle();

    // Presionar Encolar Mensaje
    await tester.tap(find.text('Encolar Mensaje'));
    await tester.pumpAndSettle();

    expect(syncQueueService.pendingCountNotifier.value, equals(1));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Mensaje Encolado en Outbox'), findsOneWidget);
  });

  testWidgets('4. Forzar sincronización dispara el proceso de la cola', (tester) async {
    connectivityService.toggleOfflineSimulation(false);

    final manualCoordinator = ChatSyncCoordinator(
      connectivityService: connectivityService,
      syncQueueService: syncQueueService,
      localStorage: localChatStorage,
      chatService: mockChatService,
      autoStart: false,
    );

    final msg = ChatMessage(
      id: 'test_sync_btn_msg',
      chatId: 'c1',
      senderId: 'usr_me',
      content: 'Contenido a sincronizar',
      type: MessageType.text,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      isSynced: false,
    );
    await syncQueueService.enqueueMessage(msg);

    await tester.pumpWidget(
      MaterialApp(
        home: OfflineSyncView(
          connectivityService: connectivityService,
          syncQueueService: syncQueueService,
          syncCoordinator: manualCoordinator,
          localChatStorage: localChatStorage,
          notificationService: notificationService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(syncQueueService.pendingCountNotifier.value, equals(1));
    expect(mockChatService.processedCount, equals(0));

    final forceSyncFinder = find.text('Forzar Sincro');
    await tester.ensureVisible(forceSyncFinder);
    await tester.tap(forceSyncFinder);

    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();

    expect(mockChatService.processedCount, equals(1));
    expect(syncQueueService.pendingCountNotifier.value, equals(0));

    manualCoordinator.dispose();
  });

  testWidgets('5. Disparar push simulada genera notificación en pantalla', (tester) async {
    await tester.pumpWidget(buildTestableSyncView());
    await tester.pumpAndSettle();

    final pushButtonFinder = find.text('Disparar Push Simulada');
    await tester.ensureVisible(pushButtonFinder);
    await tester.tap(pushButtonFinder);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Mensaje nuevo de @experto_fin'), findsOneWidget);
    expect(find.text('¿Revisaste el balance en la outbox? Sincronización exitosa.'), findsOneWidget);
  });
}
