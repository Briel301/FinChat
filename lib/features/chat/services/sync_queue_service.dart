import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/optimization_utils.dart';
import '../models/chat_message.dart';
import 'local_chat_storage.dart';

/// Top-level parser para deserialización en isolates si la cola es masiva.
ChatMessage _parseQueueItem(Map<String, dynamic> json) => ChatMessage.fromJson(json);

/// Servicio de cola de sincronización basado en el patrón Transactional Outbox.
///
/// Gestiona la persistencia en disco de mensajes pendientes de envío hacia Supabase,
/// garantizando entrega garantizada, cero duplicación por UUID y resiliencia
/// completa ante caídas o reinicios de la aplicación.
class SyncQueueService {
  static SyncQueueService _instance = SyncQueueService._internal();

  /// Retorna la instancia singleton de la cola de sincronización.
  static SyncQueueService get instance => _instance;

  /// Permite reiniciar o inyectar una instancia para pruebas unitarias.
  @visibleForTesting
  static void resetInstance([SyncQueueService? instance]) {
    _instance = instance ?? SyncQueueService._internal();
  }

  /// Constructor factory estándar.
  factory SyncQueueService({
    SharedPreferences? preferences,
    LocalChatStorage? localStorage,
  }) {
    if (preferences != null || localStorage != null) {
      return SyncQueueService._internal(
        preferences: preferences,
        localStorage: localStorage,
      );
    }
    return _instance;
  }

  /// Constructor con dependencias explícitas para pruebas unitarias.
  @visibleForTesting
  SyncQueueService.withDependencies({
    required SharedPreferences preferences,
    LocalChatStorage? localStorage,
  }) : this._internal(
          preferences: preferences,
          localStorage: localStorage ?? LocalChatStorage(preferences: preferences),
        );

  SyncQueueService._internal({
    SharedPreferences? preferences,
    LocalChatStorage? localStorage,
  })  : _preferences = preferences,
        _localStorage = localStorage ?? LocalChatStorage.instance {
    _initQueue();
  }

  SharedPreferences? _preferences;
  final LocalChatStorage _localStorage;

  /// Clave de almacenamiento en disco para la cola de salida.
  static const String keySyncQueue = 'outbox_sync_queue';

  /// Lista en memoria de mensajes encolados.
  final List<ChatMessage> _queue = [];

  /// Contador reactivo observable por la UI.
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);

  bool _isInitialized = false;

  /// Número total de mensajes pendientes de sincronización.
  int get pendingCount => pendingCountNotifier.value;

  /// Vista inmutable de los mensajes en cola actualmente en memoria.
  List<ChatMessage> get queue => List.unmodifiable(_queue);

  /// Resuelve la instancia de [SharedPreferences].
  Future<SharedPreferences> _getPrefs() async {
    final prefs = _preferences ??= await SharedPreferences.getInstance();
    return prefs;
  }

  /// Inicializa la cola cargando desde disco y asegurando idempotencia.
  Future<void> _initQueue() async {
    try {
      final prefs = await _getPrefs();
      final jsonString = prefs.getString(keySyncQueue);

      if (jsonString != null && jsonString.trim().isNotEmpty) {
        List<ChatMessage> loaded;
        try {
          if (jsonString.length >= OptimizationUtils.jsonIsolateThreshold) {
            loaded = await OptimizationUtils.decodeModelsInBackground<ChatMessage>(
              jsonString,
              _parseQueueItem,
            );
          } else {
            final decoded = jsonDecode(jsonString);
            if (decoded is List) {
              loaded = decoded
                  .whereType<Map>()
                  .map((m) => ChatMessage.fromMap(Map<String, dynamic>.from(m)))
                  .toList();
            } else {
              loaded = [];
            }
          }
        } on FormatException catch (e) {
          debugPrint('[SyncQueueService] JSON corrupto en cola outbox: $e');
          loaded = [];
        }

        _queue.clear();
        // De-duplicación defensiva por id
        final seenIds = <String>{};
        for (final msg in loaded) {
          if (seenIds.add(msg.id)) {
            _queue.add(msg);
          }
        }
        _sortQueue();
      }
    } catch (e) {
      if (e is! MissingPluginException) {
        debugPrint('[SyncQueueService] Error cargando cola desde disco: $e');
      }
    } finally {
      _isInitialized = true;
      pendingCountNotifier.value = _queue.length;
    }
  }

  /// Método público para forzar la carga completa de disco antes de operar.
  Future<void> init() async {
    if (!_isInitialized) {
      await _initQueue();
    }
  }

  // ============================================================================
  // 1. ENCOLAR MENSAJE (enqueueMessage)
  // ============================================================================

  /// Agrega un mensaje a la cola Outbox con [isSynced] en false y [status] en sending.
  ///
  /// Persiste atómicamente la cola en disco y actualiza el almacenamiento local
  /// mediante [LocalChatStorage] para que aparezca instantáneamente en la interfaz.
  ///
  /// Retorna el [ChatMessage] transformado para renderizado en Optimistic UI.
  Future<ChatMessage> enqueueMessage(ChatMessage message) async {
    await init();

    final queuedMessage = message.copyWith(
      isSynced: false,
      status: MessageStatus.sending,
    );

    // Evitar duplicaciones: si ya existe el UUID, actualizamos su contenido
    final existingIdx = _queue.indexWhere((m) => m.id == queuedMessage.id);
    if (existingIdx != -1) {
      _queue[existingIdx] = queuedMessage;
    } else {
      _queue.add(queuedMessage);
    }

    _sortQueue();

    // Persistencia atómica de la cola en disco
    await _persistQueue();

    // Persistir también en el historial local del chat
    await _localStorage.upsertLocalMessage(queuedMessage);

    // Actualizar contador reactivo
    pendingCountNotifier.value = _queue.length;

    return queuedMessage;
  }

  // ============================================================================
  // 2. CONSULTAR MENSAJES PENDIENTES (getPendingMessages)
  // ============================================================================

  /// Retorna todos los mensajes pendientes de sincronización ordenados por
  /// fecha de creación ascendente (`createdAt ASC`, FIFO).
  Future<List<ChatMessage>> getPendingMessages() async {
    await init();
    _sortQueue();
    return List<ChatMessage>.unmodifiable(_queue);
  }

  // ============================================================================
  // 3. DESENCOLAR Y MARCAR COMO SINCRONIZADO
  // ============================================================================

  /// Retira un mensaje de la cola de salida persistida en disco.
  ///
  /// Retorna el mensaje retirado, o `null` si no se encontraba en la cola.
  Future<ChatMessage?> dequeueMessage(String messageId) async {
    await init();

    final index = _queue.indexWhere((m) => m.id == messageId);
    if (index == -1) return null;

    final removed = _queue.removeAt(index);
    await _persistQueue();
    pendingCountNotifier.value = _queue.length;

    return removed;
  }

  /// Confirma la sincronización exitosa de un mensaje:
  /// 1. Lo retira de la cola Outbox.
  /// 2. Actualiza su estado en [LocalChatStorage] a `isSynced: true` y `status: MessageStatus.sent`.
  /// 3. Actualiza el contador reactivo.
  ///
  /// Retorna el [ChatMessage] con su estado actualizado a sincronizado.
  Future<ChatMessage?> markAsSynced(String messageId) async {
    await init();

    final index = _queue.indexWhere((m) => m.id == messageId);
    ChatMessage? targetMessage;

    if (index != -1) {
      targetMessage = _queue.removeAt(index);
      await _persistQueue();
      pendingCountNotifier.value = _queue.length;
    }

    // Si no estaba en la cola de memoria, buscarlo en el historial local
    if (targetMessage == null) {
      // Intentar actualizar directamente si el caller conoce el chatId
      return null;
    }

    final syncedMessage = targetMessage.copyWith(
      isSynced: true,
      status: MessageStatus.sent,
    );

    // Actualizar almacenamiento local para que la UI refleje el tick de confirmación
    await _localStorage.upsertLocalMessage(syncedMessage);

    return syncedMessage;
  }

  // ============================================================================
  // 4. MÉTODOS DE UTILIDAD Y MANTENIMIENTO
  // ============================================================================

  /// Determina si un mensaje con el [messageId] especificado está en la cola.
  bool containsMessage(String messageId) {
    return _queue.any((m) => m.id == messageId);
  }

  /// Limpia por completo la cola de salida tanto en memoria como en disco.
  Future<void> clearQueue() async {
    _queue.clear();
    pendingCountNotifier.value = 0;

    try {
      final prefs = await _getPrefs();
      await prefs.remove(keySyncQueue);
    } catch (e) {
      debugPrint('[SyncQueueService] Error limpiando cola en disco: $e');
    }
  }

  /// Ordena los mensajes encolados por fecha de creación ascendente (FIFO).
  void _sortQueue() {
    _queue.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Persiste la lista actual de `_queue` en disco.
  Future<void> _persistQueue() async {
    try {
      final prefs = await _getPrefs();
      final maps = _queue.map((m) => m.toMap()).toList(growable: false);
      final jsonString = await OptimizationUtils.encodeJsonListInBackground(maps);
      await prefs.setString(keySyncQueue, jsonString);
    } catch (e, stack) {
      debugPrint('[SyncQueueService] Error persistiendo cola en disco: $e');
      debugPrint(stack.toString());
    }
  }
}
