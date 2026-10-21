import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finchat/core/theme/app_theme.dart';
import 'package:finchat/features/chat/models/chat_message.dart';
import 'package:finchat/features/chat/models/conversation_summary.dart';
import 'package:finchat/features/chat/providers/chat_provider.dart';
import 'package:finchat/features/chat/services/chat_service.dart';
import 'package:finchat/features/chat/views/chat_room_view.dart';
import 'package:finchat/features/chat/views/conversations_list_view.dart';
import 'package:finchat/features/chat/views/widgets/message_bubble_widget.dart';
import 'package:finchat/features/users/providers/user_provider.dart';

class MockChatServiceForViews extends ChatService {
  MockChatServiceForViews() : super.test();

  final List<ChatMessage> inMemoryMessages = [
    ChatMessage(
      id: 'msg_01',
      chatId: 'chat_test',
      senderId: 'usr_peer',
      content: '¡Hola! ¿Cómo estás?',
      type: MessageType.text,
      status: MessageStatus.read,
      createdAt: DateTime.utc(2026, 10, 11, 8, 0, 0),
      isSynced: true,
    ),
    ChatMessage(
      id: 'msg_02',
      chatId: 'chat_test',
      senderId: 'usr_me',
      content: 'Todo excelente, probando FinChat.',
      type: MessageType.text,
      status: MessageStatus.sent,
      createdAt: DateTime.utc(2026, 10, 11, 8, 5, 0),
      isSynced: true,
      isFromMe: true,
    ),
  ];

  @override
  Future<List<ConversationSummary>> loadConversations() async {
    return [
      ConversationSummary(
        chatId: 'chat_test',
        otherUserId: 'usr_peer',
        otherUsername: 'fin_expert',
        otherFullName: 'Experto Financiero',
        lastMessageContent: 'Todo excelente, probando FinChat.',
        lastMessageTime: DateTime.utc(2026, 10, 11, 8, 5, 0),
        unreadCount: 3,
      ),
    ];
  }

  @override
  Future<List<ChatMessage>> loadChatHistory(String chatId) async {
    return List.from(inMemoryMessages);
  }

  @override
  Future<ChatMessage> sendMessage(ChatMessage message) async {
    inMemoryMessages.add(message);
    return message.copyWith(status: MessageStatus.sent, isSynced: true);
  }

  @override
  void subscribeToChat(String chatId, {required void Function(ChatMessage message) onNewMessage}) {}

  @override
  void unsubscribeFromChat(String chatId) {}
}

void main() {
  late MockChatServiceForViews mockService;
  late ChatProvider chatProvider;
  late UserProvider userProvider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockService = MockChatServiceForViews();
    chatProvider = ChatProvider(
      chatService: mockService,
      currentUserId: 'usr_me',
    );
    userProvider = UserProvider();
  });

  Widget buildTestableWidget(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: chatProvider),
        ChangeNotifierProvider.value(value: userProvider),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: child,
      ),
    );
  }

  group('MessageBubbleWidget Tests', () {
    testWidgets('Mensaje propio se alinea a la derecha y muestra checks', (tester) async {
      final msg = ChatMessage(
        id: 'msg_own',
        chatId: 'c1',
        senderId: 'usr_me',
        content: 'Transferencia autorizada por \$5,000 MXN',
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.utc(2026, 10, 11, 10, 30, 0),
        isSynced: true,
      );

      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: MessageBubbleWidget(
              message: msg,
              isMine: true,
            ),
          ),
        ),
      );

      expect(find.text('Transferencia autorizada por \$5,000 MXN'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      final alignWidget = tester.widget<Align>(
        find.ancestor(
          of: find.text('Transferencia autorizada por \$5,000 MXN'),
          matching: find.byType(Align),
        ).first,
      );
      expect(alignWidget.alignment, Alignment.centerRight);
    });

    testWidgets('Mensaje recibido se alinea a la izquierda sin checks de envío propios', (tester) async {
      final msg = ChatMessage(
        id: 'msg_incoming',
        chatId: 'c1',
        senderId: 'usr_peer',
        content: 'Recibo confirmado, gracias.',
        type: MessageType.text,
        status: MessageStatus.read,
        createdAt: DateTime.utc(2026, 10, 11, 10, 31, 0),
        isSynced: true,
      );

      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: MessageBubbleWidget(
              message: msg,
              isMine: false,
            ),
          ),
        ),
      );

      expect(find.text('Recibo confirmado, gracias.'), findsOneWidget);
      // No debe renderizar check para mensajes entrantes
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      final alignWidget = tester.widget<Align>(
        find.ancestor(
          of: find.text('Recibo confirmado, gracias.'),
          matching: find.byType(Align),
        ).first,
      );
      expect(alignWidget.alignment, Alignment.centerLeft);
    });

    testWidgets('Mensaje pendiente offline muestra reloj tenue y tooltip accesible', (tester) async {
      final msg = ChatMessage(
        id: 'msg_offline',
        chatId: 'c1',
        senderId: 'usr_me',
        content: 'Mensaje pendiente en túnel',
        type: MessageType.text,
        status: MessageStatus.sending,
        createdAt: DateTime.utc(2026, 10, 11, 10, 32, 0),
        isSynced: false,
        isFromMe: true,
      );

      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: MessageBubbleWidget(
              message: msg,
              isMine: true,
            ),
          ),
        ),
      );

      expect(find.text('Mensaje pendiente en túnel'), findsOneWidget);
      expect(find.byIcon(Icons.access_time_rounded), findsOneWidget);
      expect(find.byTooltip('Pendiente de sincronizar (Offline)'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('Mensaje leído muestra doble check y tooltip Leído', (tester) async {
      final msg = ChatMessage(
        id: 'msg_read',
        chatId: 'c1',
        senderId: 'usr_me',
        content: '¿Recibiste el depósito?',
        type: MessageType.text,
        status: MessageStatus.read,
        createdAt: DateTime.utc(2026, 10, 11, 10, 33, 0),
        isSynced: true,
        isFromMe: true,
      );

      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: MessageBubbleWidget(
              message: msg,
              isMine: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.byTooltip('Leído'), findsOneWidget);
    });

    testWidgets('Mensaje con fallo muestra icono de advertencia e invoca onRetry', (tester) async {
      bool retryTapped = false;
      final msg = ChatMessage(
        id: 'msg_failed',
        chatId: 'c1',
        senderId: 'usr_me',
        content: 'Error de red forzado',
        type: MessageType.text,
        status: MessageStatus.failed,
        createdAt: DateTime.utc(2026, 10, 11, 10, 34, 0),
        isSynced: false,
        isFromMe: true,
      );

      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: MessageBubbleWidget(
              message: msg,
              isMine: true,
              onRetry: () => retryTapped = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byTooltip('Error de envío. Toca para reintentar.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.error_outline_rounded));
      await tester.pump();
      expect(retryTapped, isTrue);
    });
  });

  group('ConversationsListView Tests', () {
    testWidgets('Muestra AppBar FinChat, FAB e ítem de conversación con insignias', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(const ConversationsListView()),
      );

      // Esperar resolución de postFrameCallback
      await tester.pumpAndSettle();

      expect(find.text('FinChat'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Experto Financiero'), findsOneWidget);
      expect(find.text('Todo excelente, probando FinChat.'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // Badge de no leídos
    });

    testWidgets('Tocar conversación navega a ChatRoomView', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(const ConversationsListView()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Experto Financiero'));
      await tester.pumpAndSettle();

      // Debe estar en ChatRoomView con datos del contacto
      expect(find.text('Experto Financiero'), findsOneWidget);
      expect(find.text('En línea'), findsOneWidget);
      expect(find.byType(ChatRoomView), findsOneWidget);
    });
  });

  group('ChatRoomView Tests', () {
    testWidgets('Muestra mensajes con reverse scroll y envía nuevo mensaje al tipear', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const ChatRoomView(
            chatId: 'chat_test',
            otherUserId: 'usr_peer',
            otherUsername: 'fin_expert',
            otherFullName: 'Experto Financiero',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('¡Hola! ¿Cómo estás?'), findsOneWidget);
      expect(find.text('Todo excelente, probando FinChat.'), findsOneWidget);

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.reverse, isTrue);

      // El campo de texto está listo
      final inputField = find.byType(TextField);
      expect(inputField, findsOneWidget);

      // Escribir mensaje
      await tester.enterText(inputField, 'Nuevo mensaje optimista');
      await tester.pump();

      // El botón de enviar ahora debe tener icono send
      final sendButton = find.byIcon(Icons.send_rounded);
      expect(sendButton, findsOneWidget);

      // Pulsar enviar
      await tester.tap(sendButton);
      await tester.pump(); // Inmediato Optimistic UI

      // Debe aparecer de inmediato en pantalla
      expect(find.text('Nuevo mensaje optimista'), findsOneWidget);

      await tester.pumpAndSettle();
    });
  });
}
