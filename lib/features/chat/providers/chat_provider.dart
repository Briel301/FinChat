import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/supabase/supabase_config.dart';
import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import '../services/chat_service.dart';
import '../services/chat_sync_coordinator.dart';
import '../services/local_chat_storage.dart';
import '../services/sync_queue_service.dart';

/// Proveedor de estado para la gestión reactiva del chat en FinChat.
///
/// Adopta una arquitectura **Cache-First (Stale-While-Revalidate)**:
/// - Lectura instantánea (0 ms) desde almacenamiento local ([LocalChatStorage]).
/// - Revalidación silenciosa y actualización de deltas desde Supabase.
/// - Flujo de envío offline resiliente apoyado en el patrón Outbox ([SyncQueueService]).
/// - Coordinación reactiva de eventos con [ChatSyncCoordinator].
class ChatProvider extends ChangeNotifier {
  final ChatService _chatService;
  final LocalChatStorage _localStorage;
  final SyncQueueService _syncQueueService;
  final ConnectivityService _connectivityService;
  final ChatSyncCoordinator? _syncCoordinator;
  final String _currentUserId;

  StreamSubscription<ChatMessage>? _coordinatorSubscription;

  // --- Estado de la Bandeja de Entrada (Inbox) ---
  List<ConversationSummary> _conversations = [];
  bool _isLoadingConversations = false;

  // --- Estado de la Sala de Chat Activa ---
  String? _activeChatId;
  final List<ChatMessage> _currentMessages = [];
  bool _isLoadingHistory = false;
  String? _errorMessage;

  ChatProvider({
    ChatService? chatService,
    LocalChatStorage? localChatStorage,
    SyncQueueService? syncQueueService,
    ConnectivityService? connectivityService,
    ChatSyncCoordinator? syncCoordinator,
    String? currentUserId,
  })  : _chatService = chatService ?? ChatService(),
        _localStorage = localChatStorage ?? LocalChatStorage.instance,
        _syncQueueService = syncQueueService ?? SyncQueueService.instance,
        _connectivityService = connectivityService ?? ConnectivityService(),
        _syncCoordinator = syncCoordinator,
        _currentUserId = currentUserId ?? _resolveCurrentUserId() {
    _initCoordinatorSubscription();
  }

  // --- Getters de Acceso Público ---
  List<ConversationSummary> get conversations => List.unmodifiable(_conversations);
  bool get isLoadingConversations => _isLoadingConversations;

  String? get activeChatId => _activeChatId;
  List<ChatMessage> get currentMessages => List.unmodifiable(_currentMessages);
  bool get isLoadingHistory => _isLoadingHistory;
  String? get errorMessage => _errorMessage;
  String get currentUserId => _currentUserId;

  LocalChatStorage get localStorage => _localStorage;
  SyncQueueService get syncQueueService => _syncQueueService;
  ConnectivityService get connectivityService => _connectivityService;
  ChatSyncCoordinator? get syncCoordinator => _syncCoordinator;

  static String _resolveCurrentUserId() {
    if (SupabaseConfig.isInitialized) {
      return SupabaseConfig.auth.currentUser?.id ?? 'usr_me';
    }
    return 'usr_me';
  }

  void _initCoordinatorSubscription() {
    _coordinatorSubscription =
        _syncCoordinator?.onMessageSyncedStream.listen(_handleSyncedMessage);
  }

  /// Maneja los mensajes despachados exitosamente por el coordinador.
  void _handleSyncedMessage(ChatMessage synced) {
    if (_activeChatId == synced.chatId) {
      final index = _currentMessages.indexWhere((m) => m.id == synced.id);
      if (index != -1) {
        _currentMessages[index] = synced.copyWith(
          status: MessageStatus.sent,
          isSynced: true,
        );
        _updateConversationLastMessage(_currentMessages[index]);
        notifyListeners();
      }
    }
  }

  // ============================================================================
  // 1. GESTIÓN DE LA BANDEJA DE ENTRADA (CACHE-FIRST / STALE-WHILE-REVALIDATE)
  // ============================================================================

  /// Carga la lista de conversaciones recientes con latencia percibida de 0 ms.
  Future<void> loadConversations() async {
    _isLoadingConversations = true;
    _errorMessage = null;
    notifyListeners();

    // 1. Cache-First: Lectura instantánea desde almacenamiento local
    try {
      final cached = await _localStorage.getCachedConversations();
      if (cached.isNotEmpty) {
        _conversations = List<ConversationSummary>.from(cached);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ChatProvider] Error leyendo caché local de conversaciones: $e');
    }

    // 2. Revalidate: Si hay conexión, refrescar en segundo plano desde Supabase
    try {
      if (_connectivityService.isOnline) {
        final loaded = await _chatService.loadConversations();
        _conversations = List<ConversationSummary>.from(loaded);
        await _localStorage.saveConversations(_conversations);
      } else if (_conversations.isEmpty) {
        final loaded = await _chatService.loadConversations();
        _conversations = List<ConversationSummary>.from(loaded);
      }
    } catch (e) {
      if (_conversations.isEmpty) {
        _errorMessage = 'Error al cargar las conversaciones: $e';
      }
    } finally {
      _isLoadingConversations = false;
      notifyListeners();
    }
  }

  // ============================================================================
  // 2. ENTRADA Y SALIDA DE LA SALA DE CHAT (CACHE-FIRST)
  // ============================================================================

  /// Ingresa a una conversación, carga el historial local de inmediato (0 ms)
  /// y revalida deltas con Supabase en segundo plano.
  Future<void> enterChat(String chatId) async {
    if (chatId.isEmpty) return;

    // Evitar recarga innecesaria si ya estamos en la sala
    if (_activeChatId == chatId && _currentMessages.isNotEmpty) {
      return;
    }

    // Liberar canal anterior si cambiamos de sala
    if (_activeChatId != null && _activeChatId != chatId) {
      leaveChat();
    }

    _activeChatId = chatId;
    _isLoadingHistory = true;
    _errorMessage = null;
    _currentMessages.clear();
    notifyListeners();

    // 1. Cache-First: Cargar historial local inmediatamente (0 ms)
    try {
      final cached = await _localStorage.getCachedMessages(chatId);
      if (cached.isNotEmpty) {
        _currentMessages.clear();
        _currentMessages.addAll(cached);
        _sortMessages();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ChatProvider] Error leyendo historial local en enterChat: $e');
    }

    // 2. Revalidate: Si hay conexión a internet, traer mensajes recientes de Supabase
    try {
      if (_connectivityService.isOnline) {
        final history = await _chatService.loadChatHistory(chatId);
        _currentMessages.clear();
        _currentMessages.addAll(history);
        _sortMessages();
        await _localStorage.saveMessages(chatId, _currentMessages);
      } else if (_currentMessages.isEmpty) {
        final history = await _chatService.loadChatHistory(chatId);
        _currentMessages.clear();
        _currentMessages.addAll(history);
        _sortMessages();
      }
    } catch (e) {
      if (_currentMessages.isEmpty) {
        _errorMessage = 'Error al cargar el historial del chat: $e';
      }
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }

    // 3. Conectar WebSocket de Realtime
    _chatService.subscribeToChat(
      chatId,
      onNewMessage: _handleIncomingWebSocketMessage,
    );
  }

  /// Cancela la suscripción a WebSockets y libera el estado al abandonar la vista de la sala.
  void leaveChat() {
    final chatId = _activeChatId;
    if (chatId != null) {
      _chatService.unsubscribeFromChat(chatId);
      _activeChatId = null;
      _currentMessages.clear();
      notifyListeners();
    }
  }

  // ============================================================================
  // 3. FLUJO DE ENVÍO OPTIMISTA & OUTBOX PERSISTENTE
  // ============================================================================

  /// Envía un mensaje de texto con renderizado optimista inmediato y persistencia Outbox.
  Future<void> sendTextMessage(String content) async {
    final trimmedText = content.trim();
    if (trimmedText.isEmpty) return;

    final chatId = _activeChatId;
    if (chatId == null) {
      _errorMessage = 'No hay ninguna sala de conversación activa.';
      notifyListeners();
      return;
    }

    // 1. Generar nuevo ChatMessage con UUIDv4 cliente y estado inicial 'sending'
    final messageId = const Uuid().v4();
    final optimisticMessage = ChatMessage(
      id: messageId,
      chatId: chatId,
      senderId: _currentUserId,
      content: trimmedText,
      type: MessageType.text,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      isSynced: false,
      isFromMe: true,
    );

    // 2. Renderizado Inmediato (Optimistic UI): Latencia 0 ms síncrona en pantalla
    _currentMessages.add(optimisticMessage);
    _sortMessages();
    _updateConversationLastMessage(optimisticMessage);
    notifyListeners();

    // 3. Persistir en cola Outbox y almacenamiento local
    await _syncQueueService.enqueueMessage(optimisticMessage);

    // 4. Si hay red, sincronizar de inmediato con el backend
    if (_connectivityService.isOnline) {
      try {
        final serverResponse = await _chatService.sendMessage(optimisticMessage);
        await _syncQueueService.markAsSynced(messageId);

        final index = _currentMessages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _currentMessages[index] = serverResponse.copyWith(
            status: MessageStatus.sent,
            isSynced: true,
          );
          _updateConversationLastMessage(_currentMessages[index]);
          notifyListeners();
        }
      } catch (error) {
        // En caso de fallo explícito de red/servidor
        final index = _currentMessages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _currentMessages[index] = _currentMessages[index].copyWith(
            status: MessageStatus.failed,
            isSynced: false,
          );
          _errorMessage = 'No se pudo entregar el mensaje: $error';
          notifyListeners();
        }
      }
    }
    // Si está offline: permanece con estado 'sending' e 'isSynced: false' en la sala sin arrojar errores
  }

  // ============================================================================
  // 4. MANEJO DE EVENTOS WEBSOCKET EN TIEMPO REAL
  // ============================================================================

  /// Callback invocado cuando Supabase Realtime emite un nuevo mensaje.
  void _handleIncomingWebSocketMessage(ChatMessage message) {
    if (_activeChatId == null || message.chatId != _activeChatId) {
      _updateConversationLastMessage(message);
      notifyListeners();
      return;
    }

    final existingIndex = _currentMessages.indexWhere((m) => m.id == message.id);
    if (existingIndex != -1) {
      _currentMessages[existingIndex] = message;
    } else {
      _currentMessages.add(message);
      _sortMessages();
    }

    _updateConversationLastMessage(message);
    notifyListeners();
  }

  /// Reintenta el envío de un mensaje que quedó en estado fallido.
  Future<void> retryMessage(String messageId) async {
    final index = _currentMessages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    final failedMessage = _currentMessages[index];
    final retryingMessage = failedMessage.copyWith(
      status: MessageStatus.sending,
      isSynced: false,
    );

    _currentMessages[index] = retryingMessage;
    notifyListeners();

    try {
      final serverResponse = await _chatService.sendMessage(retryingMessage);
      await _syncQueueService.markAsSynced(messageId);

      final refreshedIndex = _currentMessages.indexWhere((m) => m.id == messageId);
      if (refreshedIndex != -1) {
        _currentMessages[refreshedIndex] = serverResponse.copyWith(
          status: MessageStatus.sent,
          isSynced: true,
        );
        notifyListeners();
      }
    } catch (e) {
      final refreshedIndex = _currentMessages.indexWhere((m) => m.id == messageId);
      if (refreshedIndex != -1) {
        _currentMessages[refreshedIndex] = _currentMessages[refreshedIndex].copyWith(
          status: MessageStatus.failed,
          isSynced: false,
        );
        _errorMessage = 'Reintento fallido: $e';
        notifyListeners();
      }
    }
  }

  // ============================================================================
  // 5. UTILIDADES PRIVADAS DE ORDENAMIENTO Y ACTUALIZACIÓN
  // ============================================================================

  void _sortMessages() {
    _currentMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  void _updateConversationLastMessage(ChatMessage message) {
    final convIndex = _conversations.indexWhere((c) => c.chatId == message.chatId);
    if (convIndex != -1) {
      final current = _conversations[convIndex];
      final isIncoming = !message.isMine(_currentUserId);
      final updated = current.copyWith(
        lastMessageContent: message.content,
        lastMessageTime: message.createdAt,
        unreadCount: (_activeChatId == message.chatId || !isIncoming)
            ? current.unreadCount
            : current.unreadCount + 1,
      );

      _conversations.removeAt(convIndex);
      _conversations.insert(0, updated);
    }
  }

  @override
  void dispose() {
    _coordinatorSubscription?.cancel();
    _coordinatorSubscription = null;
    leaveChat();
    super.dispose();
  }
}
