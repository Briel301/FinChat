import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/optimization_utils.dart';
import '../models/chat_message.dart';
import '../models/conversation_summary.dart';

/// Funciones top-level transferibles entre isolates para decodificación no bloqueante.
ChatMessage _parseChatMessage(Map<String, dynamic> json) => ChatMessage.fromJson(json);
ConversationSummary _parseConversationSummary(Map<String, dynamic> json) =>
    ConversationSummary.fromJson(json);

/// Gestor de persistencia local y caché en disco para FinChat (Offline-First).
///
/// Implementa una arquitectura de caché en dos niveles:
/// - **L1 (Memoria RAM)**: Latencia 0 ms para lecturas repetidas instantáneas.
/// - **L2 (Disco / SharedPreferences)**: Persistencia atómica en el sandbox del dispositivo.
///
/// Para lotes de mensajes voluminosos, delega la serialización/deserialización
/// a isolates secundarios mediante [OptimizationUtils] para evitar jank en la UI.
class LocalChatStorage {
  static LocalChatStorage _instance = LocalChatStorage._internal();

  /// Retorna la instancia compartida singleton.
  static LocalChatStorage get instance => _instance;

  /// Permite inyectar o sustituir la instancia para pruebas unitarias.
  @visibleForTesting
  static void resetInstance([LocalChatStorage? instance]) {
    _instance = instance ?? LocalChatStorage._internal();
  }

  /// Constructor factory estándar.
  factory LocalChatStorage({SharedPreferences? preferences}) {
    if (preferences != null) {
      return LocalChatStorage._internal(preferences: preferences);
    }
    return _instance;
  }

  /// Constructor con inyección explícita para pruebas unitarias.
  @visibleForTesting
  LocalChatStorage.withPreferences(SharedPreferences preferences)
      : this._internal(preferences: preferences);

  LocalChatStorage._internal({SharedPreferences? preferences})
      : _preferences = preferences;

  SharedPreferences? _preferences;

  // --- Prefijos y Claves de Persistencia Local ---
  static const String keyMessagesPrefix = 'cache_messages_';
  static const String keyConversations = 'cache_conversations_inbox';
  static const String keyChatIndex = 'cache_chat_index';
  static const String keyLastAccessedPrefix = 'cache_last_accessed_';

  // --- Caché L1 en memoria (Latencia 0 ms) ---
  final Map<String, List<ChatMessage>> _memoryMessagesCache = {};
  List<ConversationSummary>? _memoryConversationsCache;

  /// Inicializa o resuelve la instancia de [SharedPreferences].
  Future<SharedPreferences> _getPrefs() async {
    final prefs = _preferences ??= await SharedPreferences.getInstance();
    return prefs;
  }

  /// Pre-inicializa el almacenamiento y carga el índice de chats en memoria.
  Future<void> init() async {
    await _getPrefs();
  }

  // ============================================================================
  // 1. GUARDADO DE HISTORIAL LOCAL (saveMessages)
  // ============================================================================

  /// Serializa y guarda atómicamente la lista de mensajes de un chat en disco.
  ///
  /// Actualiza inmediatamente la caché L1 en memoria y el registro de acceso para LRU.
  Future<void> saveMessages(String chatId, List<ChatMessage> messages) async {
    if (chatId.isEmpty) return;

    // 1. Clonar y ordenar cronológicamente
    final sortedMessages = List<ChatMessage>.from(messages)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // 2. Actualizar caché L1 en memoria de inmediato
    _memoryMessagesCache[chatId] = List<ChatMessage>.unmodifiable(sortedMessages);

    try {
      final prefs = await _getPrefs();

      // 3. Serializar a lista de mapas
      final maps = sortedMessages.map((m) => m.toMap()).toList(growable: false);

      // 4. Codificar a JSON (en isolate si supera el umbral)
      final jsonString = await OptimizationUtils.encodeJsonListInBackground(maps);

      // 5. Escritura atómica en SharedPreferences
      await prefs.setString('$keyMessagesPrefix$chatId', jsonString);

      // 6. Actualizar metadatos de cuota e índice
      await _recordChatAccess(chatId, prefs);
    } catch (e, stack) {
      debugPrint('[LocalChatStorage] Error guardando mensajes de $chatId en disco: $e');
      debugPrint(stack.toString());
      // No re-lanzamos: la caché L1 ya contiene los mensajes para la sesión actual
    }
  }

  // ============================================================================
  // 2. LECTURA DE CACHÉ DE MENSAJES (getCachedMessages)
  // ============================================================================

  /// Lee los mensajes guardados de un chat con latencia 0 ms si están en memoria.
  ///
  /// Si no existen datos previos o el JSON está corrupto, retorna una lista vacía `[]`.
  Future<List<ChatMessage>> getCachedMessages(String chatId) async {
    if (chatId.isEmpty) return const [];

    // Verificación L1 (Memoria): Retorno instantáneo (0 ms)
    final memoryHit = _memoryMessagesCache[chatId];
    if (memoryHit != null) {
      return memoryHit;
    }

    try {
      final prefs = await _getPrefs();
      final key = '$keyMessagesPrefix$chatId';
      final jsonString = prefs.getString(key);

      if (jsonString == null || jsonString.trim().isEmpty) {
        _memoryMessagesCache[chatId] = const [];
        return const [];
      }

      // Deserialización defensiva con soporte para background isolate
      List<ChatMessage> deserialized;
      try {
        if (jsonString.length >= OptimizationUtils.jsonIsolateThreshold) {
          deserialized = await OptimizationUtils.decodeModelsInBackground<ChatMessage>(
            jsonString,
            _parseChatMessage,
          );
        } else {
          final decoded = jsonDecode(jsonString);
          if (decoded is List) {
            deserialized = decoded
                .whereType<Map>()
                .map((item) => ChatMessage.fromMap(Map<String, dynamic>.from(item)))
                .toList(growable: false);
          } else {
            deserialized = const [];
          }
        }
      } on FormatException catch (e) {
        debugPrint('[LocalChatStorage] JSON corrupto detectado para $chatId: $e');
        deserialized = const [];
      }

      // Asegurar orden cronológico y registrar en L1
      final sorted = List<ChatMessage>.from(deserialized)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final unmodifiable = List<ChatMessage>.unmodifiable(sorted);
      _memoryMessagesCache[chatId] = unmodifiable;
      return unmodifiable;
    } catch (e) {
      debugPrint('[LocalChatStorage] Excepción leyendo caché de $chatId: $e');
      return const [];
    }
  }

  /// Acceso sincrónico directo a la caché L1 en memoria (0 ms garantizado).
  List<ChatMessage> getCachedMessagesSync(String chatId) {
    return _memoryMessagesCache[chatId] ?? const [];
  }

  // ============================================================================
  // 3. INSERCIÓN / ACTUALIZACIÓN INDIVIDUAL (upsertLocalMessage)
  // ============================================================================

  /// Agrega un nuevo mensaje o actualiza uno existente en disco y memoria.
  ///
  /// Es ideal para actualizar estados en vivo (`sending` -> `sent` o `isSynced`).
  Future<ChatMessage> upsertLocalMessage(
    ChatMessage message, {
    String? chatId,
  }) async {
    final targetChatId = chatId ?? message.chatId;
    if (targetChatId.isEmpty) return message;

    // Obtener historial actual (desde memoria o disco)
    final currentList = await getCachedMessages(targetChatId);
    final mutableList = List<ChatMessage>.from(currentList);

    final existingIndex = mutableList.indexWhere((m) => m.id == message.id);
    if (existingIndex != -1) {
      mutableList[existingIndex] = message;
    } else {
      mutableList.add(message);
    }

    // Persistir de forma atómica en disco y L1
    await saveMessages(targetChatId, mutableList);
    return message;
  }

  // ============================================================================
  // 4. CACHÉ DE LISTA DE CONVERSACIONES (INBOX)
  // ============================================================================

  /// Guarda la bandeja de entrada completa para consulta offline/modo avión.
  Future<void> saveConversations(List<ConversationSummary> conversations) async {
    final sorted = List<ConversationSummary>.from(conversations)
      ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

    _memoryConversationsCache = List<ConversationSummary>.unmodifiable(sorted);

    try {
      final prefs = await _getPrefs();
      final maps = sorted.map((c) => c.toMap()).toList(growable: false);
      final jsonString = await OptimizationUtils.encodeJsonListInBackground(maps);
      await prefs.setString(keyConversations, jsonString);
    } catch (e, stack) {
      debugPrint('[LocalChatStorage] Error guardando conversaciones en disco: $e');
      debugPrint(stack.toString());
    }
  }

  /// Recupera las conversaciones cacheadas con soporte offline inmediato.
  Future<List<ConversationSummary>> getCachedConversations() async {
    if (_memoryConversationsCache != null) {
      return _memoryConversationsCache!;
    }

    try {
      final prefs = await _getPrefs();
      final jsonString = prefs.getString(keyConversations);

      if (jsonString == null || jsonString.trim().isEmpty) {
        _memoryConversationsCache = const [];
        return const [];
      }

      List<ConversationSummary> list;
      try {
        if (jsonString.length >= OptimizationUtils.jsonIsolateThreshold) {
          list = await OptimizationUtils.decodeModelsInBackground<ConversationSummary>(
            jsonString,
            _parseConversationSummary,
          );
        } else {
          final decoded = jsonDecode(jsonString);
          if (decoded is List) {
            list = decoded
                .whereType<Map>()
                .map((m) => ConversationSummary.fromMap(Map<String, dynamic>.from(m)))
                .toList(growable: false);
          } else {
            list = const [];
          }
        }
      } on FormatException catch (e) {
        debugPrint('[LocalChatStorage] JSON corrupto en conversaciones: $e');
        list = const [];
      }

      final sorted = List<ConversationSummary>.from(list)
        ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

      _memoryConversationsCache = List<ConversationSummary>.unmodifiable(sorted);
      return _memoryConversationsCache!;
    } catch (e) {
      debugPrint('[LocalChatStorage] Excepción leyendo conversaciones en disco: $e');
      return const [];
    }
  }

  /// Acceso sincrónico a las conversaciones en memoria.
  List<ConversationSummary> getCachedConversationsSync() {
    return _memoryConversationsCache ?? const [];
  }

  // ============================================================================
  // 5. LIMPIEZA, PURGA Y GESTIÓN DE CUOTA
  // ============================================================================

  /// Elimina los mensajes almacenados de un chat específico en memoria y disco.
  Future<void> clearChatCache(String chatId) async {
    if (chatId.isEmpty) return;

    _memoryMessagesCache.remove(chatId);

    try {
      final prefs = await _getPrefs();
      await prefs.remove('$keyMessagesPrefix$chatId');
      await prefs.remove('$keyLastAccessedPrefix$chatId');

      final indexList = prefs.getStringList(keyChatIndex) ?? [];
      if (indexList.contains(chatId)) {
        indexList.remove(chatId);
        await prefs.setStringList(keyChatIndex, indexList);
      }
    } catch (e) {
      debugPrint('[LocalChatStorage] Error limpiando chat $chatId: $e');
    }
  }

  /// Poda mensajes antiguos de un chat si excede [maxMessages], reteniendo los más recientes.
  ///
  /// Retorna la cantidad de mensajes purgados.
  Future<int> purgeOldMessages({
    required String chatId,
    int maxMessages = 100,
  }) async {
    if (chatId.isEmpty || maxMessages <= 0) return 0;

    final currentMessages = await getCachedMessages(chatId);
    if (currentMessages.length <= maxMessages) {
      return 0;
    }

    final excessCount = currentMessages.length - maxMessages;
    // Como están ordenados ascendente por createdAt, tomamos los últimos maxMessages
    final trimmedMessages = currentMessages.sublist(excessCount);

    await saveMessages(chatId, trimmedMessages);
    return excessCount;
  }

  /// Aplica políticas de cuota en el almacenamiento local:
  /// 1. Poda mensajes que excedan [maxMessagesPerChat] por conversación.
  /// 2. Si el número total de chats supera [maxTotalChats], elimina los chats menos
  ///    recientemente accedidos (LRU).
  ///
  /// Retorna el número total de registros/chats purgados.
  Future<int> enforceStorageQuota({
    int maxMessagesPerChat = 100,
    int maxTotalChats = 50,
  }) async {
    int purgedCount = 0;

    try {
      final prefs = await _getPrefs();
      final indexedChats = prefs.getStringList(keyChatIndex) ?? [];

      // 1. Podar mensajes dentro de cada chat
      for (final chatId in List<String>.from(indexedChats)) {
        final pruned = await purgeOldMessages(
          chatId: chatId,
          maxMessages: maxMessagesPerChat,
        );
        purgedCount += pruned;
      }

      // 2. Si el número de chats supera la cuota máxima, purgar chats antiguos (LRU)
      if (indexedChats.length > maxTotalChats) {
        final chatsWithTimestamps = <String, int>{};
        for (final chatId in indexedChats) {
          final timestamp = prefs.getInt('$keyLastAccessedPrefix$chatId') ?? 0;
          chatsWithTimestamps[chatId] = timestamp;
        }

        // Ordenar de más antiguo a más reciente
        final sortedByLRU = indexedChats.toList()
          ..sort((a, b) => (chatsWithTimestamps[a] ?? 0).compareTo(chatsWithTimestamps[b] ?? 0));

        final excessChats = indexedChats.length - maxTotalChats;
        final chatsToRemove = sortedByLRU.take(excessChats).toList();

        for (final chatToRemove in chatsToRemove) {
          await clearChatCache(chatToRemove);
          purgedCount++;
        }
      }
    } catch (e) {
      debugPrint('[LocalChatStorage] Error aplicando cuota de almacenamiento: $e');
    }

    return purgedCount;
  }

  /// Limpia por completo toda la caché local de FinChat (memoria y disco).
  Future<void> clearAllCache() async {
    _memoryMessagesCache.clear();
    _memoryConversationsCache = null;

    try {
      final prefs = await _getPrefs();
      final indexedChats = prefs.getStringList(keyChatIndex) ?? [];

      for (final chatId in indexedChats) {
        await prefs.remove('$keyMessagesPrefix$chatId');
        await prefs.remove('$keyLastAccessedPrefix$chatId');
      }

      await prefs.remove(keyConversations);
      await prefs.remove(keyChatIndex);
    } catch (e) {
      debugPrint('[LocalChatStorage] Error al limpiar todo el caché: $e');
    }
  }

  /// Registra el acceso a un chat y lo añade al índice si no existía.
  Future<void> _recordChatAccess(String chatId, SharedPreferences prefs) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt('$keyLastAccessedPrefix$chatId', nowMs);

    final indexList = prefs.getStringList(keyChatIndex) ?? [];
    if (!indexList.contains(chatId)) {
      indexList.add(chatId);
      await prefs.setStringList(keyChatIndex, indexList);
    }
  }
}
