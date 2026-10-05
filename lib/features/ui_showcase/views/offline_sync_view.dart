import 'package:flutter/material.dart';
import '../../chat/services/chat_service.dart';
import '../../notifications/services/notification_service.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';

/// Vista interactiva para validar la arquitectura Offline (Should Have: 7 pts)
/// y las Notificaciones Push en segundo plano (Should Have: 8 pts).
class OfflineSyncView extends StatefulWidget {
  const OfflineSyncView({super.key});

  @override
  State<OfflineSyncView> createState() => _OfflineSyncViewState();
}

class _OfflineSyncViewState extends State<OfflineSyncView> {
  final _connectivityService = ConnectivityService();
  final _chatService = ChatService();
  final _notificationService = NotificationService();

  String? _syncStatusMessage;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_connectivityService, _chatService, _notificationService]),
      builder: (context, _) {
        final isOnline = _connectivityService.isOnline;
        final isSimulated = _connectivityService.isSimulatedOffline;
        final pendingCount = _chatService.pendingSyncCount;
        final messages = _chatService.messages;
        final lastPushTitle = _notificationService.lastNotificationTitle;
        final lastPushBody = _notificationService.lastNotificationBody;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Modo Offline & Notificaciones Push'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tarjeta Should Have MoSCoW
                Card(
                  color: Colors.teal.shade50,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_off, color: Colors.teal),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Should Have (15 pts totales): Arquitectura Offline (ver mensajes sin internet: 7 pts) + Notificaciones Push en segundo plano/cerrada (8 pts).',
                            style: TextStyle(fontSize: 13, color: Colors.teal.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Control del Interruptor Offline
                Card(
                  child: SwitchListTile(
                    title: const Text('Simular Desconexión (Modo Avión)', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      isSimulated 
                          ? 'Desconectado: La app lee de la base de datos local (SQLite/Hive)' 
                          : 'Conectado a Supabase en tiempo real',
                      style: TextStyle(color: isSimulated ? Colors.red : Colors.green),
                    ),
                    value: isSimulated,
                    activeColor: Colors.red,
                    onChanged: (val) {
                      _connectivityService.toggleOfflineSimulation(val);
                      if (!val) {
                        // Al reconectar, sincroniza automáticamente
                        _chatService.syncPendingMessages().then((synced) {
                          setState(() {
                            _syncStatusMessage = '¡Conexión restablecida! Se sincronizaron $synced mensajes con Supabase.';
                          });
                        });
                      } else {
                        setState(() => _syncStatusMessage = null);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Mensajes en Cola Pendiente
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: pendingCount > 0 ? Colors.amber.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: pendingCount > 0 ? Colors.amber : Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(pendingCount > 0 ? Icons.sync_problem : Icons.cloud_done, 
                              color: pendingCount > 0 ? Colors.orange.shade800 : Colors.blue.shade800),
                          const SizedBox(width: 8),
                          Text(
                            'Mensajes pendientes en cola local: $pendingCount',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Los mensajes se guardan primero en el disco del dispositivo. Aunque no haya conexión, el historial completo permanece disponible.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                      if (pendingCount > 0 && isOnline) ...[
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final synced = await _chatService.syncPendingMessages();
                            setState(() {
                              _syncStatusMessage = 'Sincronizados $synced mensajes.';
                            });
                          },
                          icon: const Icon(Icons.sync),
                          label: const Text('Forzar Sincronización Ahora'),
                        ),
                      ],
                    ],
                  ),
                ),

                if (_syncStatusMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _syncStatusMessage!,
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ],
                const SizedBox(height: 24),

                // Sección de Notificaciones Push
                const Text('Prueba de Notificaciones Push (Segundo Plano)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    _notificationService.simulateIncomingPush(
                      senderUsername: 'usuario1',
                      messageText: '¿Revisaste los audios comprimidos? Quedaron en 240 KB.',
                    );
                  },
                  icon: const Icon(Icons.notifications_active),
                  label: const Text('Disparar Notificación Push Simulada'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                ),
                const SizedBox(height: 12),

                // Tarjeta simuladora de Notificación del Sistema Operativo
                if (lastPushTitle != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
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
                              Text(lastPushBody ?? '', style: const TextStyle(fontSize: 13, color: AppTheme.textDark)),
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
                const SizedBox(height: 24),

                // Vista previa de los mensajes en caché local
                const Text('Historial Disponible en Caché Local:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          msg.isSynced ? Icons.cloud_done : Icons.cloud_off,
                          color: msg.isSynced ? Colors.green : Colors.orange,
                        ),
                        title: Text(msg.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '@${msg.senderUsername} • ${msg.isSynced ? "Sincronizado" : "Guardado en caché local"}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Text(
                          '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
