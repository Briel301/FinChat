import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../users/views/user_profile_screen.dart';
import '../services/direct_chat_repository.dart';

/// Pantalla de conversación privada 1:1 en tiempo real vinculada por ID único inmutable (`UUID`)
/// con soporte para envío y visualización de imágenes desde galería/cámara y perfil de contacto.
class RealChatScreen extends StatefulWidget {
  final String currentUserId;
  final String currentUserName;
  final String recipientUserId;
  final String recipientName;
  final String? initialRecipientAvatarUrl;
  final String? initialRecipientBio;
  final String initialRecipientFullName;

  const RealChatScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.recipientUserId,
    required this.recipientName,
    this.initialRecipientAvatarUrl,
    this.initialRecipientBio,
    this.initialRecipientFullName = '',
  });

  @override
  State<RealChatScreen> createState() => _RealChatScreenState();
}

class _RealChatScreenState extends State<RealChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _realtimeChannel;
  Timer? _syncTimer;

  late String _currentUserId;
  late String _currentUserName;
  late String _recipientName;
  String? _recipientAvatarUrl;
  String? _recipientBio;
  String _recipientFullName = '';

  bool _isLoadingMessages = true;
  bool _isSending = false;
  bool _isUploadingMedia = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = widget.currentUserId;
    _currentUserName = widget.currentUserName;
    _recipientName = widget.recipientName;
    _recipientAvatarUrl = widget.initialRecipientAvatarUrl;
    _recipientBio = widget.initialRecipientBio;
    _recipientFullName = widget.initialRecipientFullName;
    _initChat();
  }

  /// Se ejecuta también en Hot Reload para asegurar que el canal y timer estén activos
  @override
  void reassemble() {
    super.reassemble();
    _initChat();
  }

  void _initChat() {
    _fetchMessages();
    _refreshRecipientProfile();
    _subscribeToRealtime();
    _startBackgroundSync();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _startBackgroundSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _fetchMessages();
      _refreshRecipientProfile();
    });
  }

  Future<void> _refreshRecipientProfile() async {
    if (widget.recipientUserId.isEmpty) return;
    try {
      final data = await DirectChatRepository.instance.fetchUserProfile(widget.recipientUserId);

      if (data != null && mounted) {
        final updatedName = (data['username'] ?? '').toString().trim();
        final updatedAvatar = (data['avatar_url'] ?? '').toString().trim();
        final updatedBio = (data['bio'] ?? '').toString().trim();
        final updatedFullName = (data['full_name'] ?? '').toString().trim();

        setState(() {
          if (updatedName.isNotEmpty) _recipientName = updatedName;
          _recipientAvatarUrl = updatedAvatar.isNotEmpty ? updatedAvatar : null;
          _recipientBio = updatedBio.isNotEmpty ? updatedBio : null;
          _recipientFullName = updatedFullName;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchMessages() async {
    if (_currentUserId.isEmpty) return;

    try {
      final fetchedList = await DirectChatRepository.instance.fetchDirectMessages(
        currentUserId: _currentUserId,
        otherUserId: widget.recipientUserId,
        currentUserName: _currentUserName,
        otherUserName: _recipientName,
      );

      if (!mounted) return;

      bool hasChanges = fetchedList.length != _messages.length;
      if (!hasChanges && fetchedList.isNotEmpty && _messages.isNotEmpty) {
        hasChanges = fetchedList.last['id'] != _messages.last['id'];
      }

      if (hasChanges || _isLoadingMessages) {
        setState(() {
          _messages = fetchedList;
          _isLoadingMessages = false;
        });
        if (hasChanges) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('[RealChatScreen] Error al sincronizar mensajes 1:1: $e');
      if (mounted && _isLoadingMessages) {
        setState(() {
          _isLoadingMessages = false;
        });
      }
    }
  }

  void _subscribeToRealtime() {
    _realtimeChannel?.unsubscribe();
    final channelName = 'dm_live_${DateTime.now().millisecondsSinceEpoch}';
    _realtimeChannel = SupabaseConfig.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: SupabaseConfig.tableMessages,
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.insert) {
              final raw = payload.newRecord;
              if (raw.isNotEmpty) {
                final normalized = DirectChatRepository.instance.normalizeMessage(raw);
                if (normalized != null &&
                    DirectChatRepository.instance.isMessageBetween(
                      normalizedMsg: normalized,
                      currentUserId: _currentUserId,
                      otherUserId: widget.recipientUserId,
                      currentUserName: _currentUserName,
                      otherUserName: _recipientName,
                    )) {
                  _addOrUpdateMessage(normalized);
                }
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: SupabaseConfig.tableProfiles,
          callback: (payload) {
            final updated = payload.newRecord;
            if (updated['id']?.toString() == widget.recipientUserId && mounted) {
              final newName = (updated['username'] ?? '').toString().trim();
              final newAvatar = (updated['avatar_url'] ?? '').toString().trim();
              final newBio = (updated['bio'] ?? '').toString().trim();
              final newFullName = (updated['full_name'] ?? '').toString().trim();
              setState(() {
                if (newName.isNotEmpty) _recipientName = newName;
                _recipientAvatarUrl = newAvatar.isNotEmpty ? newAvatar : null;
                _recipientBio = newBio.isNotEmpty ? newBio : null;
                _recipientFullName = newFullName;
              });
            }
          },
        )
        .subscribe();
  }

  void _addOrUpdateMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final id = msg['id'];
    final index = _messages.indexWhere((m) => m['id'] == id);

    if (index == -1) {
      setState(() {
        _messages.add(msg);
        _messages.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showRecipientProfile() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ContactProfileSheet(
        userId: widget.recipientUserId,
        username: _recipientName,
        fullName: _recipientFullName,
        bio: _recipientBio,
        avatarUrl: _recipientAvatarUrl,
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending || _currentUserId.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    _textController.clear();

    try {
      final inserted = await DirectChatRepository.instance.sendDirectMessage(
        senderId: _currentUserId,
        receiverId: widget.recipientUserId,
        senderName: _currentUserName,
        content: text,
      );

      _addOrUpdateMessage(inserted);
    } catch (e) {
      debugPrint('[RealChatScreen] Error al enviar mensaje 1:1: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  /// Permite seleccionar una imagen de la galería o tomar una foto con la cámara,
  /// previsualizarla, añadir un comentario opcional y enviarla a la conversación.
  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_isUploadingMedia || _currentUserId.isEmpty) return;

    try {
      final XFile? picked = await DirectChatRepository.instance.pickOrCaptureImage(source);

      if (picked == null || !mounted) return;

      final rawBytes = await picked.readAsBytes();
      if (!mounted) return;

      final captionController = TextEditingController(text: _textController.text.trim());
      final bool? shouldSend = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final kbSize = (rawBytes.length / 1024).toStringAsFixed(1);
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  source == ImageSource.camera ? Icons.camera_alt : Icons.photo_library,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Enviar imagen',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: Image.memory(
                        rawBytes,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tamaño: $kbSize KB',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: captionController,
                    decoration: const InputDecoration(
                      hintText: 'Añadir un comentario (opcional)...',
                      prefixIcon: Icon(Icons.chat_bubble_outline, size: 20),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: const Icon(Icons.send, size: 18),
                label: const Text('Enviar'),
              ),
            ],
          );
        },
      );

      if (shouldSend != true || !mounted) return;

      final caption = captionController.text.trim();
      _textController.clear();

      setState(() {
        _isUploadingMedia = true;
      });

      final optimizedBytes = await DirectChatRepository.instance.compressImageBytes(rawBytes);
      final ext = picked.name.contains('.') ? picked.name.split('.').last.toLowerCase() : 'jpg';
      final contentType = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';

      final publicUrl = await DirectChatRepository.instance.uploadMediaBytes(
        bucket: SupabaseConfig.bucketChatImages,
        bytes: optimizedBytes,
        fileName: picked.name.isNotEmpty ? picked.name : 'photo.jpg',
        contentType: contentType,
      );

      final inserted = await DirectChatRepository.instance.sendDirectMessage(
        senderId: _currentUserId,
        receiverId: widget.recipientUserId,
        senderName: _currentUserName,
        content: caption,
        mediaUrl: publicUrl,
        mediaType: 'image',
        fileSizeBytes: optimizedBytes.length,
      );

      _addOrUpdateMessage(inserted);
    } catch (e) {
      debugPrint('[RealChatScreen] Error al subir/enviar imagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al capturar/enviar imagen: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingMedia = false;
        });
      }
    }
  }

  /// Abre un visor en pantalla completa con zoom para inspeccionar una imagen recibida o enviada.
  void _openFullScreenImage(String imageUrl, String senderName, String caption) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(senderName, style: const TextStyle(fontSize: 16)),
                  if (caption.isNotEmpty)
                    Text(
                      caption,
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            body: Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                        SizedBox(height: 12),
                        Text(
                          'No se pudo cargar la imagen',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null) return '';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      return DateFormat('hh:mm a').format(dateTime);
    } catch (_) {
      return '';
    }
  }

  Widget _buildMessageContent({
    required Map<String, dynamic> msg,
    required bool isMe,
  }) {
    final content = (msg['content'] ?? '').toString();
    final mediaUrl = msg['media_url']?.toString();
    final mediaType = (msg['media_type'] ?? 'text').toString();
    final senderName = (msg['sender_name'] ?? 'Usuario').toString();

    final textColor = isMe
        ? Colors.white
        : Theme.of(context).textTheme.bodyLarge?.color;

    if (mediaType == 'image' && mediaUrl != null && mediaUrl.isNotEmpty) {
      return Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openFullScreenImage(mediaUrl, senderName, content),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 240,
                  maxHeight: 280,
                  minWidth: 120,
                  minHeight: 100,
                ),
                child: Image.network(
                  mediaUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: 200,
                      height: 160,
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isMe ? Colors.white : AppTheme.primaryColor,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 200,
                      height: 120,
                      padding: const EdgeInsets.all(12),
                      color: Colors.black12,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image_outlined,
                            color: isMe ? Colors.white70 : Colors.grey,
                            size: 32,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Imagen no disponible',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: isMe ? Colors.white70 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              content,
              style: TextStyle(fontSize: 15, color: textColor),
            ),
          ],
        ],
      );
    }

    return Text(
      content,
      style: TextStyle(fontSize: 15, color: textColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitleBio = (_recipientBio != null && _recipientBio!.trim().isNotEmpty)
        ? _recipientBio!.trim()
        : 'Toca para ver info del contacto';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _showRecipientProfile,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                UserAvatarWidget(
                  userId: widget.recipientUserId,
                  username: _recipientName,
                  avatarUrl: _recipientAvatarUrl,
                  radius: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _recipientName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 11,
                            color: Colors.greenAccent,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              subtitleBio,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Ver perfil del contacto',
            onPressed: _showRecipientProfile,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Sincronizar mensajes',
            onPressed: _fetchMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isUploadingMedia)
            const LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: Colors.transparent,
            ),
          Expanded(
            child: _isLoadingMessages
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchMessages,
                    child: _messages.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.28),
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Column(
                                    children: [
                                      UserAvatarWidget(
                                        userId: widget.recipientUserId,
                                        username: _recipientName,
                                        avatarUrl: _recipientAvatarUrl,
                                        radius: 40,
                                        onTap: _showRecipientProfile,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Conversación 1:1 con $_recipientName',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Envía mensajes de texto, fotos desde tu galería o capturadas con la cámara.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 13, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final msgSenderId = (msg['sender_id'] ?? '').toString();
                              final senderName = (msg['sender_name'] ?? 'Anónimo').toString();
                              final timestamp = _formatTimestamp(msg['created_at']?.toString());

                              final isMe = msgSenderId.isNotEmpty
                                  ? msgSenderId == _currentUserId
                                  : senderName.trim().toLowerCase() ==
                                      _currentUserName.trim().toLowerCase();

                              return Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? AppTheme.primaryColor
                                        : Theme.of(context).brightness == Brightness.dark
                                            ? Colors.grey.shade800
                                            : Colors.grey.shade200,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft:
                                          isMe ? const Radius.circular(16) : const Radius.circular(2),
                                      bottomRight:
                                          isMe ? const Radius.circular(2) : const Radius.circular(16),
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                    children: [
                                      _buildMessageContent(msg: msg, isMe: isMe),
                                      const SizedBox(height: 4),
                                      Text(
                                        timestamp,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isMe ? Colors.white70 : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),

          // Barra inferior de entrada de texto y botones multimedia
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_library_outlined),
                    tooltip: 'Seleccionar imagen de galería',
                    color: AppTheme.primaryColor,
                    onPressed: (_isUploadingMedia || _isSending)
                        ? null
                        : () => _pickAndSendImage(ImageSource.gallery),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_outlined),
                    tooltip: 'Tomar foto con la cámara',
                    color: AppTheme.primaryColor,
                    onPressed: (_isUploadingMedia || _isSending)
                        ? null
                        : () => _pickAndSendImage(ImageSource.camera),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Mensaje para $_recipientName...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.shade900
                            : Colors.grey.shade100,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: (_isSending || _isUploadingMedia) ? null : _sendMessage,
                    icon: (_isSending || _isUploadingMedia)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
