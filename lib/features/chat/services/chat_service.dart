import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/supabase/supabase_config.dart';
import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import 'local_chat_storage.dart';
import 'sync_queue_service.dart';

/// Servicio centralizado de chat en tiempo real con soporte Offline-First,
/// integración de Supabase Realtime (WebSockets) y caché en memoria y disco.
class ChatService extends ChangeNotifier {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;

  final LocalChatStorage _storage;
  final SyncQueueService _syncQueue;
  LocalChatStorage get storage => _storage;
  SyncQueueService get syncQueue => _syncQueue;

  @visibleForTesting
  ChatService.test({
    LocalChatStorage? storage,
    SyncQueueService? syncQueue,
  })  : _storage = storage ?? LocalChatStorage.instance,
        _syncQueue = syncQueue ?? SyncQueueService.instance;

  ChatService._internal({
    LocalChatStorage? storage,
    SyncQueueService? syncQueue,
  })  : _storage = storage ?? LocalChatStorage.instance,
        _syncQueue = syncQueue ?? SyncQueueService.instance {
    _initDefaultMessages();
  }

  static const String defaultChatId = 'chat_default';

  final List<ChatMessage> _messages = [];
  final Map<String, List<ChatMessage>> _messagesByChat = {};
  final Map<String, RealtimeChannel> _activeChannels = {};
  final Map<String, void Function(ChatMessage message)> _realtimeListeners = {};
  bool _isRecipientTyping = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isRecipientTyping => _isRecipientTyping;

  /// Cantidad de mensajes pendientes de sincronización por estar offline.
  int get pendingSyncCount {
    if (_syncQueue.pendingCount > 0) return _syncQueue.pendingCount;
    return _messages.where((m) => !m.isSynced).length +
        _messagesByChat.values
            .expand((list) => list)
            .where((m) => !m.isSynced)
            .length;
  }

  void _initDefaultMessages() {
    final now = DateTime.now().toUtc();
    final initialList = [
      ChatMessage(
        id: 'msg_001',
        chatId: defaultChatId,
        senderId: 'usr_001',
        senderUsername: 'usuario1',
        content: '¡Hola! Bienvenido a FinChat. ¿Pudiste revisar los requerimientos?',
        type: MessageType.text,
        status: MessageStatus.read,
        createdAt: now.subtract(const Duration(minutes: 15)),
        isFromMe: false,
        isSynced: true,
      ),
      ChatMessage(
        id: 'msg_002',
        chatId: defaultChatId,
        senderId: 'usr_me',
        senderUsername: 'yo',
        content: '¡Sí! Ya configuramos la arquitectura modular con Supabase y modo offline.',
        type: MessageType.text,
        status: MessageStatus.read,
        createdAt: now.subtract(const Duration(minutes: 10)),
        isFromMe: true,
        isSynced: true,
      ),
    ];

    _messages.addAll(initialList);
    _messagesByChat[defaultChatId] = List<ChatMessage>.from(initialList);
    _storage.saveMessages(defaultChatId, initialList);
  }

  /// Carga las conversaciones para la bandeja de entrada (Inbox).
  Future<List<ConversationSummary>> loadConversations() async {
    final now = DateTime.now().toUtc();

    // Si Supabase está inicializado y con red, intentar cargar desde la base de datos
    if (SupabaseConfig.isInitialized && ConnectivityService().isOnline) {
      try {
        final currentUserId = SupabaseConfig.auth.currentUser?.id;
        if (currentUserId != null) {
          final response = await SupabaseConfig.client
              .from('chat_participants')
              .select('chat_id, chats(id, updated_at), profiles!chat_participants_user_id_fkey(id, username, full_name, avatar_url)')
              .neq('user_id', currentUserId)
              .limit(30);

          if (response.isNotEmpty) {
            final List<ConversationSummary> fetched = [];
            for (final row in response) {
              final map = row;
              final chatId = map['chat_id']?.toString() ?? '';
              final profile = map['profiles'] as Map<String, dynamic>?;
              final chats = map['chats'] as Map<String, dynamic>?;

              final lastMsg = _messagesByChat[chatId]?.lastOrNull;

              fetched.add(ConversationSummary(
                chatId: chatId,
                otherUserId: profile?['id']?.toString() ?? '',
                otherUsername: profile?['username']?.toString() ?? 'usuario',
                otherFullName: profile?['full_name']?.toString(),
                otherAvatarUrl: profile?['avatar_url']?.toString(),
                lastMessageContent: lastMsg?.content ?? 'Conversación activa',
                lastMessageTime: lastMsg?.createdAt ??
                    (chats?['updated_at'] != null
                        ? DateTime.tryParse(chats!['updated_at'].toString())?.toUtc() ?? now
                        : now),
                unreadCount: 0,
              ));
            }
            if (fetched.isNotEmpty) {
              await _storage.saveConversations(fetched);
              return fetched;
            }
          }
        }
      } catch (e) {
        debugPrint('[ChatService] Error consultando Supabase chats: $e');
      }
    }

    // Verificar si existen conversaciones en caché local (modo offline)
    final cachedConversations = await _storage.getCachedConversations();
    if (cachedConversations.isNotEmpty) {
      return cachedConversations;
    }

    // Datos por defecto para demostración fluida y offline
    final defaultLast = _messages.lastOrNull;
    final defaultList = [
      ConversationSummary(
        chatId: defaultChatId,
        otherUserId: 'usr_001',
        otherUsername: 'usuario1',
        otherFullName: 'Soporte FinChat',
        otherAvatarUrl: null,
        lastMessageContent: defaultLast?.content ?? '¡Hola! Bienvenido a FinChat.',
        lastMessageTime: defaultLast?.createdAt ?? now.subtract(const Duration(minutes: 10)),
        unreadCount: 0,
      ),
      ConversationSummary(
        chatId: 'chat_demo_02',
        otherUserId: 'usr_002',
        otherUsername: 'fin_advisor',
        otherFullName: 'Asesor Financiero',
        otherAvatarUrl: null,
        lastMessageContent: 'Reporte mensual de transferencias disponible.',
        lastMessageTime: now.subtract(const Duration(hours: 2)),
        unreadCount: 1,
      ),
    ];
    await _storage.saveConversations(defaultList);
    return defaultList;
  }

  /// Carga el historial de una sala de chat por su identificador.
  Future<List<ChatMessage>> loadChatHistory(String chatId) async {
    if (SupabaseConfig.isInitialized && ConnectivityService().isOnline) {
      try {
        final response = await SupabaseConfig.client
            .from(SupabaseConfig.tableMessages)
            .select()
            .eq('chat_id', chatId)
            .order('created_at', ascending: true)
            .limit(50);

        if (response.isNotEmpty) {
          final history = response
              .map((row) => ChatMessage.fromMap(row))
              .toList();

          _messagesByChat[chatId] = history;
          if (chatId == defaultChatId) {
            _messages.clear();
            _messages.addAll(history);
          }
          await _storage.saveMessages(chatId, history);
          return List.unmodifiable(history);
        }
      } catch (e) {
        debugPrint('[ChatService] Error cargando historial desde Supabase: $e');
      }
    }

    // Cargar desde almacenamiento local para respuesta offline / instantánea
    final cached = await _storage.getCachedMessages(chatId);
    if (cached.isNotEmpty) {
      _messagesByChat[chatId] = List<ChatMessage>.from(cached);
      if (chatId == defaultChatId) {
        _messages.clear();
        _messages.addAll(cached);
      }
      return List.unmodifiable(cached);
    }

    if (chatId == defaultChatId) {
      return List.unmodifiable(_messages);
    }
    return List.unmodifiable(_messagesByChat[chatId] ?? []);
  }

  /// Envía un mensaje con soporte Optimistic UI.
  /// Si Supabase está disponible lo persiste en PostgreSQL; si falla o está offline,
  /// lo encola localmente.
  Future<ChatMessage> sendMessage(ChatMessage message) async {
    final isOnline = ConnectivityService().isOnline;

    if (SupabaseConfig.isInitialized && isOnline) {
      try {
        await SupabaseConfig.client
            .from(SupabaseConfig.tableMessages)
            .insert(message.toMap());

        final confirmed = message.copyWith(
          status: MessageStatus.sent,
          isSynced: true,
        );
        _addMessageLocally(confirmed);
        notifyListeners();
        return confirmed;
      } catch (e) {
        debugPrint('[ChatService] Error insertando en Supabase: $e');
        rethrow;
      }
    }

    // Modo local / offline (Transactional Outbox)
    final queuedMessage = await _syncQueue.enqueueMessage(
      message.copyWith(
        status: isOnline ? MessageStatus.delivered : MessageStatus.sending,
        isSynced: isOnline,
      ),
    );
    _addMessageLocally(queuedMessage);
    notifyListeners();

    // Simular respuesta automática si es la sala de demostración
    if (isOnline && message.chatId == defaultChatId) {
      _simulateRecipientInteraction(queuedMessage.id);
    }

    return queuedMessage;
  }

  /// Método de conveniencia para envío rápido de multimedia o texto simple.
  Future<ChatMessage> sendMediaMessage({
    required String text,
    MessageType type = MessageType.text,
    String? mediaUrl,
    int? fileSizeBytes,
    int? durationSeconds,
    String chatId = defaultChatId,
  }) async {
    final message = ChatMessage(
      id: const Uuid().v4(),
      chatId: chatId,
      senderId: 'usr_me',
      senderUsername: 'yo',
      content: text,
      type: type,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      isFromMe: true,
      isSynced: ConnectivityService().isOnline,
      mediaUrl: mediaUrl,
      fileSizeBytes: fileSizeBytes,
      durationSeconds: durationSeconds,
    );

    return sendMessage(message);
  }

  /// Suscribe en tiempo real a una sala mediante WebSockets de Supabase Realtime.
  void subscribeToChat(
    String chatId, {
    required void Function(ChatMessage message) onNewMessage,
  }) {
    _realtimeListeners[chatId] = onNewMessage;

    if (SupabaseConfig.isInitialized && !_activeChannels.containsKey(chatId)) {
      try {
        final channel = SupabaseConfig.client.channel('chat:$chatId')
          ..onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: SupabaseConfig.tableMessages,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'chat_id',
              value: chatId,
            ),
            callback: (payload) {
              final newRecord = payload.newRecord;
              final message = ChatMessage.fromMap(newRecord);
              _addMessageLocally(message);
              _realtimeListeners[chatId]?.call(message);
              notifyListeners();
            },
          )
          ..subscribe();

        _activeChannels[chatId] = channel;
      } catch (e) {
        debugPrint('[ChatService] Error suscribiendo a canal Realtime: $e');
      }
    }
  }

  /// Libera y desuscribe el canal de WebSockets al abandonar la sala.
  void unsubscribeFromChat(String chatId) {
    _realtimeListeners.remove(chatId);

    final channel = _activeChannels.remove(chatId);
    if (channel != null && SupabaseConfig.isInitialized) {
      try {
        SupabaseConfig.client.removeChannel(channel);
      } catch (e) {
        debugPrint('[ChatService] Error desuscribiendo canal: $e');
      }
    }
  }

  void _addMessageLocally(ChatMessage message) {
    final list = _messagesByChat.putIfAbsent(message.chatId, () => []);
    final index = list.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      list[index] = message;
    } else {
      list.add(message);
    }

    if (message.chatId == defaultChatId) {
      final defaultIdx = _messages.indexWhere((m) => m.id == message.id);
      if (defaultIdx != -1) {
        _messages[defaultIdx] = message;
      } else {
        _messages.add(message);
      }
    }

    _storage.upsertLocalMessage(message);
  }

  /// Sincroniza los mensajes acumulados en cola offline cuando se recupera internet.
  Future<int> syncPendingMessages() async {
    int syncedCount = 0;

    final pending = await _syncQueue.getPendingMessages();
    for (final message in pending) {
      try {
        if (SupabaseConfig.isInitialized && ConnectivityService().isOnline) {
          await SupabaseConfig.client
              .from(SupabaseConfig.tableMessages)
              .insert(message.toMap());
        }
        final synced = await _syncQueue.markAsSynced(message.id);
        if (synced != null) {
          _addMessageLocally(synced);
          syncedCount++;
        }
      } catch (e) {
        debugPrint('[ChatService] Error sincronizando mensaje en cola: $e');
      }
    }

    for (int i = 0; i < _messages.length; i++) {
      if (!_messages[i].isSynced) {
        _messages[i] = _messages[i].copyWith(
          isSynced: true,
          status: MessageStatus.delivered,
        );
        syncedCount++;
      }
    }
    if (syncedCount > 0) {
      notifyListeners();
    }
    return syncedCount;
  }

  /// Simula la interacción del otro usuario: 'escribiendo...', lectura (doble check) y respuesta.
  void _simulateRecipientInteraction(String sentMessageId) {
    Timer(const Duration(milliseconds: 900), () {
      final index = _messages.indexWhere((m) => m.id == sentMessageId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(status: MessageStatus.read);
        _isRecipientTyping = true;
        notifyListeners();
      }

      Timer(const Duration(milliseconds: 2000), () {
        _isRecipientTyping = false;
        final reply = ChatMessage(
          id: 'msg_reply_${DateTime.now().millisecondsSinceEpoch}',
          chatId: defaultChatId,
          senderId: 'usr_001',
          senderUsername: 'usuario1',
          content: 'Recibido correctamente. Funciona muy fluido.',
          type: MessageType.text,
          status: MessageStatus.read,
          createdAt: DateTime.now().toUtc(),
          isFromMe: false,
          isSynced: true,
        );

        _addMessageLocally(reply);
        _realtimeListeners[defaultChatId]?.call(reply);
        notifyListeners();
      });
    });
  }

  /// Alterna manualmente el estado del indicador 'escribiendo...' para pruebas UI.
  void setRecipientTyping(bool typing) {
    _isRecipientTyping = typing;
    notifyListeners();
  }
}
