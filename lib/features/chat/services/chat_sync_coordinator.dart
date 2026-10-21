import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../core/network/connectivity_service.dart';
import '../models/chat_message.dart';
import 'chat_service.dart';
import 'local_chat_storage.dart';
import 'sync_queue_service.dart';

/// Evento emitido cuando falla la sincronización de un mensaje encolado.
@immutable
class SyncErrorEvent {
  final String messageId;
  final Object error;
  final StackTrace? stackTrace;

  const SyncErrorEvent({
    required this.messageId,
    required this.error,
    this.stackTrace,
  });

  @override
  String toString() => 'SyncErrorEvent(messageId: $messageId, error: $error)';
}

/// Orquestador central de sincronización en segundo plano para FinChat.
///
/// Escucha en tiempo real los cambios de red reportados por [ConnectivityService]
/// y despacha automáticamente la cola de salida persistida en [SyncQueueService]
/// tan pronto como se restablece la conexión, garantizando:
///
/// 1. **Entrega secuencial**: Los mensajes se envían en estricto orden cronológico (FIFO).
/// 2. **Prevención de carreras**: Bandera de bloqueo [_isSyncing] contra ejecuciones concurrentes.
/// 3. **Resiliencia ante fallos**: Interrupción ordenada y reintento con backoff exponencial.
/// 4. **Reactividad para UI**: Callbacks, streams y notificaciones de [ChangeNotifier].
class ChatSyncCoordinator extends ChangeNotifier {
  final ConnectivityService _connectivityService;
  final SyncQueueService _syncQueueService;
  final LocalChatStorage _localStorage;
  final ChatService _chatService;

  ConnectivityService get connectivityService => _connectivityService;
  SyncQueueService get syncQueueService => _syncQueueService;
  LocalChatStorage get localStorage => _localStorage;
  ChatService get chatService => _chatService;

  final Duration initialRetryDelay;
  final Duration maxRetryDelay;
  final int maxRetries;

  // --- Callbacks opcionales para la interfaz de usuario ---
  void Function(ChatMessage message)? onMessageSynced;
  void Function(int totalSynced)? onSyncCompleted;
  void Function(String messageId, Object error)? onSyncError;

  // --- Streams reactivos de eventos de sincronización ---
  final StreamController<ChatMessage> _onMessageSyncedController =
      StreamController<ChatMessage>.broadcast();
  final StreamController<int> _onSyncCompletedController =
      StreamController<int>.broadcast();
  final StreamController<SyncErrorEvent> _onSyncErrorController =
      StreamController<SyncErrorEvent>.broadcast();

  Stream<ChatMessage> get onMessageSyncedStream => _onMessageSyncedController.stream;
  Stream<int> get onSyncCompletedStream => _onSyncCompletedController.stream;
  Stream<SyncErrorEvent> get onSyncErrorStream => _onSyncErrorController.stream;

  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _retryTimer;

  bool _isSyncing = false;
  bool _isDisposed = false;
  int _retryCount = 0;

  /// Indica si la sincronización de la cola está actualmente en curso.
  bool get isSyncing => _isSyncing;

  /// Cantidad de intentos de reintento acumulados tras el último fallo.
  int get retryCount => _retryCount;

  /// Constructor con inyección de dependencias y configuración de reintentos.
  ChatSyncCoordinator({
    ConnectivityService? connectivityService,
    SyncQueueService? syncQueueService,
    LocalChatStorage? localStorage,
    ChatService? chatService,
    this.initialRetryDelay = const Duration(seconds: 2),
    this.maxRetryDelay = const Duration(seconds: 32),
    this.maxRetries = 5,
    bool autoStart = true,
    this.onMessageSynced,
    this.onSyncCompleted,
    this.onSyncError,
  })  : _connectivityService = connectivityService ?? ConnectivityService(),
        _syncQueueService = syncQueueService ?? SyncQueueService.instance,
        _localStorage = localStorage ?? LocalChatStorage.instance,
        _chatService = chatService ?? ChatService() {
    if (autoStart) {
      startListening();
    }
  }

  /// Inicia la escucha reactiva de cambios en el estado de la red.
  void startListening() {
    if (_isDisposed || _connectivitySubscription != null) return;

    _connectivitySubscription = _connectivityService.onConnectivityChanged.listen(
      _handleConnectivityChange,
      onError: (Object error) {
        debugPrint('[ChatSyncCoordinator] Error en stream de conectividad: $error');
      },
    );

    // Si ya hay conectividad al momento de inicializar, intentar procesar
    if (_connectivityService.isOnline) {
      processQueue();
    }
  }

  /// Maneja los cambios de conectividad emitidos por [ConnectivityService].
  void _handleConnectivityChange(bool isOnline) {
    if (_isDisposed) return;

    if (isOnline) {
      debugPrint('[ChatSyncCoordinator] Conexión detectada. Iniciando despacho de outbox...');
      _retryCount = 0;
      processQueue();
    } else {
      debugPrint('[ChatSyncCoordinator] Conexión perdida. Pausando sincronización activa.');
      _cancelRetryTimer();
    }
  }

  /// Procesa secuencialmente todos los mensajes pendientes en la cola outbox.
  ///
  /// Retorna la cantidad de mensajes sincronizados exitosamente en esta tanda.
  Future<int> processQueue() async {
    if (_isDisposed) return 0;

    // Prevención de ejecuciones concurrentes o solapadas
    if (_isSyncing) {
      debugPrint('[ChatSyncCoordinator] Sincronización ya en curso. Omitiendo llamada concurrente.');
      return 0;
    }

    // No procesar si no hay conexión real a internet
    if (!_connectivityService.isOnline) {
      debugPrint('[ChatSyncCoordinator] Sin conexión a internet. Despacho cancelado.');
      return 0;
    }

    _isSyncing = true;
    _cancelRetryTimer();
    notifyListeners();

    int syncedCount = 0;

    try {
      final pendingMessages = await _syncQueueService.getPendingMessages();
      if (pendingMessages.isEmpty) {
        _retryCount = 0;
        return 0;
      }

      debugPrint('[ChatSyncCoordinator] Procesando ${pendingMessages.length} mensaje(s) en cola...');

      for (final message in pendingMessages) {
        // Interrumpir limpiamente si la red cae o se destruye el coordinador
        if (_isDisposed || !_connectivityService.isOnline) {
          debugPrint('[ChatSyncCoordinator] Conexión interrumpida durante el despacho.');
          break;
        }

        try {
          // 1. Despachar a Supabase mediante ChatService
          final confirmed = await _chatService.sendMessage(message);

          // 2. Marcar como sincronizado y desencolar de disco
          await _syncQueueService.markAsSynced(message.id);

          syncedCount++;
          _retryCount = 0; // El éxito reinicia la cuenta de reintentos

          // 3. Notificar evento a oyentes
          if (!_isDisposed) {
            _onMessageSyncedController.add(confirmed);
            onMessageSynced?.call(confirmed);
          }
        } catch (e, stack) {
          debugPrint('[ChatSyncCoordinator] Error sincronizando mensaje ${message.id}: $e');
          if (!_isDisposed) {
            final errorEvent = SyncErrorEvent(messageId: message.id, error: e, stackTrace: stack);
            _onSyncErrorController.add(errorEvent);
            onSyncError?.call(message.id, e);
          }

          // Interrumpir ciclo para preservar orden cronológico y programar backoff
          _scheduleRetry();
          break;
        }
      }

      if (syncedCount > 0 && !_isDisposed) {
        _onSyncCompletedController.add(syncedCount);
        onSyncCompleted?.call(syncedCount);
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }

    return syncedCount;
  }

  /// Programa un reintento automático con exponential backoff ligero.
  void _scheduleRetry() {
    if (_isDisposed || !_connectivityService.isOnline) return;

    if (_retryCount >= maxRetries) {
      debugPrint('[ChatSyncCoordinator] Límite máximo de reintentos alcanzado ($_retryCount).');
      return;
    }

    _retryCount++;
    final factor = 1 << (_retryCount - 1); // 1, 2, 4, 8, 16...
    final initialMs = initialRetryDelay.inMilliseconds;
    final maxMs = maxRetryDelay.inMilliseconds;
    final calculatedMs = (initialMs * factor).clamp(initialMs, maxMs);
    final delay = Duration(milliseconds: calculatedMs);

    debugPrint('[ChatSyncCoordinator] Programando reintento $_retryCount en ${delay.inMilliseconds}ms');
    _cancelRetryTimer();

    _retryTimer = Timer(delay, () {
      if (!_isDisposed && _connectivityService.isOnline) {
        processQueue();
      }
    });
  }

  /// Cancela cualquier temporizador de reintento activo.
  void _cancelRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;

    _cancelRetryTimer();

    _onMessageSyncedController.close();
    _onSyncCompletedController.close();
    _onSyncErrorController.close();

    super.dispose();
  }
}
