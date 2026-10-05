import 'package:flutter/material.dart';
import '../../chat/models/chat_message.dart';
import '../../chat/services/chat_service.dart';
import '../../media/services/media_service.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/optimization_utils.dart';
import 'media_recorder_view.dart';

/// Sala de chat 1 a 1 interactiva con soporte multimedia, compresión, doble check y offline.
class ChatPlaygroundView extends StatefulWidget {
  const ChatPlaygroundView({super.key});

  @override
  State<ChatPlaygroundView> createState() => _ChatPlaygroundViewState();
}

class _ChatPlaygroundViewState extends State<ChatPlaygroundView> {
  final _chatService = ChatService();
  final _mediaService = MediaService();
  final _connectivityService = ConnectivityService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    await _chatService.sendMessage(text: text);
    _scrollToBottom();
  }

  Future<void> _handleSendPhoto() async {
    final photo = await _mediaService.processCameraPhoto();
    await _chatService.sendMessage(
      text: '📷 Foto optimizada (${OptimizationUtils.formatBytes(photo.compressedSizeBytes)} - WebP)',
      type: MessageType.image,
      mediaUrl: photo.remoteStorageUrl,
      fileSizeBytes: photo.compressedSizeBytes,
    );
    _scrollToBottom();
  }

  Future<void> _handleSendVideo() async {
    final video = await _mediaService.processVideo();
    await _chatService.sendMessage(
      text: '🎥 Video compartido (${video.durationSeconds}s - H.264)',
      type: MessageType.video,
      mediaUrl: video.remoteStorageUrl,
      fileSizeBytes: video.compressedSizeBytes,
      durationSeconds: video.durationSeconds,
    );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_chatService, _connectivityService]),
      builder: (context, _) {
        final messages = _chatService.messages;
        final isOnline = _connectivityService.isOnline;
        final isTyping = _chatService.isRecipientTyping;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white24,
                  child: Text('U1', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'usuario1',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isTyping 
                            ? 'escribiendo...' 
                            : (isOnline ? 'en línea' : 'modo offline'),
                        style: TextStyle(
                          fontSize: 12,
                          color: isTyping ? AppTheme.blueCheckColor : Colors.white70,
                          fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Indicador de modo Offline
              IconButton(
                tooltip: isOnline ? 'Red normal' : 'Sin conexión a internet',
                icon: Icon(
                  isOnline ? Icons.wifi : Icons.wifi_off,
                  color: isOnline ? Colors.white : Colors.amberAccent,
                ),
                onPressed: () {
                  _connectivityService.toggleOfflineSimulation(!_connectivityService.isSimulatedOffline);
                  if (_connectivityService.isOnline) {
                    _chatService.syncPendingMessages();
                  }
                },
              ),
            ],
          ),
          body: Container(
            color: const Color(0xFFEFEAE2), // Fondo clásico de chat
            child: Column(
              children: [
                // Banner si se encuentra offline
                if (!isOnline)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Modo Offline: Los mensajes se guardan localmente.',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),

                // Lista de Mensajes
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return _buildMessageBubble(msg);
                    },
                  ),
                ),

                // Indicador de escribiendo
                if (isTyping)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                            ),
                            SizedBox(width: 8),
                            Text('usuario1 está escribiendo...', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Barra inferior de envío
                _buildInputBar(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isMe = msg.isFromMe;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.chatBubbleMe : AppTheme.chatBubbleOther,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 2),
            bottomRight: Radius.circular(isMe ? 2 : 12),
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Contenido según tipo
            if (msg.type == MessageType.image) ...[
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image, size: 48, color: AppTheme.primaryColor),
                      SizedBox(height: 4),
                      Text('Foto WebP (Ahorro 82%)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ] else if (msg.type == MessageType.video) ...[
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.indigo.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_circle_fill, size: 40, color: Colors.indigo),
                      const SizedBox(width: 8),
                      Text('Video (${msg.durationSeconds ?? 15}s)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ] else if (msg.type == MessageType.audio) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isMe ? Colors.white60 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.play_arrow, color: AppTheme.primaryColor, size: 28),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(value: 0.4, color: AppTheme.primaryColor, backgroundColor: Colors.grey.shade300),
                          const SizedBox(height: 4),
                          Text('Nota de voz (${OptimizationUtils.formatDuration(msg.durationSeconds ?? 0)} / máx 01:00)', style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],

            Text(
              msg.text,
              style: const TextStyle(fontSize: 15, color: AppTheme.textDark),
            ),
            const SizedBox(height: 4),

            // Timestamp y estado (Checks)
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  if (!msg.isSynced)
                    const Icon(Icons.access_time, size: 14, color: Colors.grey)
                  else if (msg.status == MessageDeliveryStatus.read)
                    const Icon(Icons.done_all, size: 16, color: AppTheme.blueCheckColor)
                  else
                    const Icon(Icons.done_all, size: 16, color: Colors.grey),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            // Botón multimedia (Cámara / Galería / Video)
            IconButton(
              icon: const Icon(Icons.camera_alt, color: AppTheme.primaryColor),
              onPressed: _handleSendPhoto,
              tooltip: 'Tomar fotografía directa (Cámara)',
            ),
            IconButton(
              icon: const Icon(Icons.videocam, color: AppTheme.primaryColor),
              onPressed: _handleSendVideo,
              tooltip: 'Enviar video',
            ),
            // Campo de texto
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  hintText: 'Mensaje...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                onSubmitted: (_) => _handleSendText(),
              ),
            ),
            // Botón de Nota de voz (conducir al grabador de 1 min)
            IconButton(
              icon: const Icon(Icons.mic, color: AppTheme.primaryColor),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MediaRecorderView()),
                );
              },
              tooltip: 'Grabar nota de voz (máx 1 min)',
            ),
            // Botón enviar
            IconButton(
              icon: const Icon(Icons.send, color: AppTheme.primaryColor),
              onPressed: _handleSendText,
            ),
          ],
        ),
      ),
    );
  }
}
