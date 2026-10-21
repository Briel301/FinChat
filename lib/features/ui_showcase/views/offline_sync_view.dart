import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/models/chat_message.dart';
import '../../chat/services/chat_service.dart';
import '../../chat/services/chat_sync_coordinator.dart';
import '../../chat/services/local_chat_storage.dart';
import '../../chat/services/sync_queue_service.dart';
import '../../notifications/services/notification_service.dart';

/// Modelo ligero para la bitácora de eventos en tiempo real.
class SyncAuditLogItem {
  final DateTime timestamp;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const SyncAuditLogItem({
    required this.timestamp,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}

/// Vista interactiva para validar la arquitectura Offline-First (Should Have: 7 pts)
/// y las Notificaciones Push en segundo plano (Should Have: 8 pts).
///
/// Permite alternar la simulación de red, monitorear la cola de salida persistida (Outbox),
/// disparar sincronizaciones manuales o automáticas, y auditar cada evento con timestamps.
class OfflineSyncView extends StatefulWidget {
  final ConnectivityService? connectivityService;
  final SyncQueueService? syncQueueService;
  final ChatSyncCoordinator? syncCoordinator;
  final LocalChatStorage? localChatStorage;
  final NotificationService? notificationService;

  const OfflineSyncView({
    super.key,
    this.connectivityService,
    this.syncQueueService,
    this.syncCoordinator,
    this.localChatStorage,
    this.notificationService,
  });

  @override
  State<OfflineSyncView> createState() => _OfflineSyncViewState();
}

class _OfflineSyncViewState extends State<OfflineSyncView> {
  late ConnectivityService _connectivityService;
  late SyncQueueService _syncQueueService;
  late LocalChatStorage _localChatStorage;
  late ChatSyncCoordinator _syncCoordinator;
  late NotificationService _notificationService;

  final List<SyncAuditLogItem> _auditLogs = [];
  final List<StreamSubscription> _subscriptions = [];
  List<ChatMessage> _pendingMessagesList = [];

  @override
  void initState() {
    super.initState();
    _initServices();
    _attachEventListeners();
    _refreshPendingMessagesList();
  }

  void _initServices() {
    _connectivityService = widget.connectivityService ?? ConnectivityService();
    _syncQueueService = widget.syncQueueService ?? SyncQueueService.instance;
    _localChatStorage = widget.localChatStorage ?? LocalChatStorage.instance;
    _notificationService = widget.notificationService ?? NotificationService();

    _syncCoordinator = widget.syncCoordinator ??
        ChatSyncCoordinator(
          connectivityService: _connectivityService,
          syncQueueService: _syncQueueService,
          localStorage: _localChatStorage,
          chatService: ChatService(),
        );

    _addLog(
      title: 'Sistema Inicializado',
      description: 'Monitor y orquestador offline conectados a la outbox.',
      icon: Icons.check_circle_outline,
      color: Colors.blue,
    );
  }

  void _attachEventListeners() {
    _connectivityService.addListener(_handleConnectivityChange);
    _syncCoordinator.addListener(_handleCoordinatorChange);
    _notificationService.addListener(_handleNotificationChange);

    _subscriptions.add(
      _syncCoordinator.onMessageSyncedStream.listen((msg) {
        _addLog(
          title: 'Mensaje Despachado',
          description: 'ID: ${msg.id.substring(0, msg.id.length > 8 ? 8 : msg.id.length)}... "${msg.content}" sincronizado con Supabase.',
          icon: Icons.cloud_done,
          color: Colors.green,
        );
        _refreshPendingMessagesList();
      }),
    );

    _subscriptions.add(
      _syncCoordinator.onSyncCompletedStream.listen((total) {
        _addLog(
          title: 'Ronda de Sincronización Completa',
          description: 'Se despacharon exitosamente $total mensaje(s) de la cola de salida.',
          icon: Icons.done_all,
          color: Colors.teal,
        );
        _refreshPendingMessagesList();
      }),
    );

    _subscriptions.add(
      _syncCoordinator.onSyncErrorStream.listen((err) {
        _addLog(
          title: 'Error de Despacho',
          description: 'Fallo al sincronizar ${err.messageId}: ${err.error}',
          icon: Icons.error_outline,
          color: Colors.red,
        );
        _refreshPendingMessagesList();
      }),
    );
  }

  void _handleConnectivityChange() {
    if (!mounted) return;
    setState(() {});
    _addLog(
      title: _connectivityService.isOnline ? 'Red Conectada' : 'Red Desconectada',
      description: _connectivityService.isOnline
          ? 'Conexión activa. El coordinador procesará la cola automáticamente.'
          : 'Modo Offline activo. Las escrituras se guardarán en outbox local.',
      icon: _connectivityService.isOnline ? Icons.wifi : Icons.wifi_off,
      color: _connectivityService.isOnline ? Colors.green : Colors.orange,
    );
  }

  void _handleCoordinatorChange() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleNotificationChange() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refreshPendingMessagesList() async {
    final list = await _syncQueueService.getPendingMessages();
    if (!mounted) return;
    setState(() {
      _pendingMessagesList = list;
    });
  }

  void _addLog({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    if (!mounted) return;
    setState(() {
      _auditLogs.insert(
        0,
        SyncAuditLogItem(
          timestamp: DateTime.now(),
          title: title,
          description: description,
          icon: icon,
          color: color,
        ),
      );
      if (_auditLogs.length > 30) {
        _auditLogs.removeLast();
      }
    });
  }

  @override
  void dispose() {
    _connectivityService.removeListener(_handleConnectivityChange);
    _syncCoordinator.removeListener(_handleCoordinatorChange);
    _notificationService.removeListener(_handleNotificationChange);
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _enqueueSimulatedMessage() async {
    final newId = const Uuid().v4();
    final testMsg = ChatMessage(
      id: newId,
      chatId: 'simulated_chat_01',
      senderId: 'usr_me',
      content: 'Mensaje de prueba #${DateTime.now().second} generado en simulador offline',
      type: MessageType.text,
      status: MessageStatus.sending,
      createdAt: DateTime.now().toUtc(),
      isSynced: false,
      isFromMe: true,
    );

    await _syncQueueService.enqueueMessage(testMsg);
    final currentCached = await _localChatStorage.getCachedMessages(testMsg.chatId);
    await _localChatStorage.saveMessages(testMsg.chatId, [...currentCached, testMsg]);

    _addLog(
      title: 'Mensaje Encolado en Outbox',
      description: 'ID: ${newId.substring(0, 8)}... listo para despacho cuando haya red.',
      icon: Icons.add_circle_outline,
      color: Colors.amber.shade800,
    );

    await _refreshPendingMessagesList();
  }

  Future<void> _forceSync() async {
    _addLog(
      title: 'Despacho Forzado Manual',
      description: 'Solicitando a ChatSyncCoordinator.processQueue()...',
      icon: Icons.sync,
      color: Colors.indigo,
    );
    await _syncCoordinator.processQueue();
    await _refreshPendingMessagesList();
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = _connectivityService.isOnline;
    final isSimulated = _connectivityService.isSimulatedOffline;
    final isSyncing = _syncCoordinator.isSyncing;
    final lastPushTitle = _notificationService.lastNotificationTitle;
    final lastPushBody = _notificationService.lastNotificationBody;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulador & Monitor Offline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refrescar cola',
            onPressed: _refreshPendingMessagesList,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Tarjeta MoSCoW Académica
            Card(
              color: isDark ? const Color(0xFF1B4332) : Colors.teal.shade50,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isDark ? Colors.teal.shade700 : Colors.teal.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.offline_pin_rounded, color: isDark ? Colors.tealAccent : Colors.teal),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Should Have (15 pts totales): Arquitectura Offline-First (persistencia local + outbox: 7 pts) y Notificaciones Push en segundo plano (8 pts).',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.teal.shade100 : Colors.teal.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Control del Interruptor Offline
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: SwitchListTile(
                title: const Text(
                  'Simular Pérdida de Red (Modo Avión)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  isSimulated
                      ? 'Desconectado forzado: La app opera exclusivamente sobre almacenamiento local'
                      : (isOnline ? 'Conectado a Supabase en tiempo real' : 'Sin conexión física de red'),
                  style: TextStyle(
                    color: isOnline ? Colors.green : Colors.red,
                    fontSize: 12.5,
                  ),
                ),
                value: isSimulated,
                activeThumbColor: Colors.red,
                activeTrackColor: Colors.red.shade200,
                onChanged: (val) {
                  _connectivityService.toggleOfflineSimulation(val);
                },
              ),
            ),
            const SizedBox(height: 16),

            // 3. Panel de Métricas en Tiempo Real (KPIs)
            Row(
              children: [
                // KPI: Estado de Red
                Expanded(
                  child: Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      child: Column(
                        children: [
                          Icon(
                            isOnline ? Icons.wifi : Icons.wifi_off,
                            color: isOnline ? Colors.green : Colors.red,
                            size: 28,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isOnline ? 'En línea' : 'Fuera de línea',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isOnline ? Colors.green : Colors.red,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isOnline ? 'Supabase Activo' : 'Caché Local Activa',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // KPI: Mensajes en Cola (Outbox)
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _syncQueueService.pendingCountNotifier,
                    builder: (context, pendingCount, _) {
                      return Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                          child: Column(
                            children: [
                              Icon(
                                pendingCount > 0 ? Icons.outbox_rounded : Icons.cloud_done_rounded,
                                color: pendingCount > 0 ? Colors.amber.shade800 : Colors.teal,
                                size: 28,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$pendingCount',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: pendingCount > 0 ? Colors.amber.shade900 : Colors.teal,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pending Outbox',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // KPI: Estado del Coordinador
                Expanded(
                  child: Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      child: Column(
                        children: [
                          isSyncing
                              ? const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                )
                              : const Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.blue,
                                  size: 28,
                                ),
                          const SizedBox(height: 6),
                          Text(
                            isSyncing ? 'Sincronizando' : 'Al día',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Orquestador',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 4. Botones de Acción Interactiva
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _enqueueSimulatedMessage,
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('Encolar Mensaje'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (!isOnline || isSyncing) ? null : _forceSync,
                    icon: isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: const Text('Forzar Sincro'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 5. Lista de Mensajes en la Outbox (si existen)
            if (_pendingMessagesList.isNotEmpty) ...[
              Text(
                'Mensajes pendientes en disco (${_pendingMessagesList.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.amber.shade50.withAlpha(128),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _pendingMessagesList.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final msg = _pendingMessagesList[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.access_time_rounded, color: Colors.orange, size: 20),
                      title: Text(msg.content, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        'ID: ${msg.id.substring(0, msg.id.length > 8 ? 8 : msg.id.length)} • ${DateFormat('HH:mm:ss').format(msg.createdAt.toLocal())}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: const Chip(
                        label: Text('Outbox', style: TextStyle(fontSize: 10, color: Colors.white)),
                        backgroundColor: Colors.orange,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],

            // 6. Historial de Eventos de Sincronización en Vivo (Live Audit Log)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Bitácora de Sincronización en Vivo:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  '${_auditLogs.length} eventos',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              ),
              child: _auditLogs.isEmpty
                  ? const Center(
                      child: Text(
                        'Sin eventos registrados aún.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _auditLogs.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      ),
                      itemBuilder: (context, index) {
                        final log = _auditLogs[index];
                        final timeStr = DateFormat('HH:mm:ss').format(log.timestamp);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(log.icon, size: 16, color: log.color),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          log.title,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: log.color,
                                          ),
                                        ),
                                        Text(
                                          timeStr,
                                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      log.description,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 24),

            // 7. Sección de Notificaciones Push MoSCoW (8 pts)
            const Text(
              'Prueba de Notificaciones Push (Segundo Plano)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () {
                _notificationService.simulateIncomingPush(
                  senderUsername: 'experto_fin',
                  messageText: '¿Revisaste el balance en la outbox? Sincronización exitosa.',
                );
              },
              icon: const Icon(Icons.notifications_active),
              label: const Text('Disparar Push Simulada'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            if (lastPushTitle != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.indigo.shade200),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      backgroundColor: Colors.indigo,
                      child: Icon(Icons.mark_chat_unread, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lastPushTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(
                            lastPushBody ?? '',
                            style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade200 : AppTheme.textDark),
                          ),
                          const SizedBox(height: 4),
                          const Text('Hace un momento • FinChat', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _notificationService.clearNotification(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
