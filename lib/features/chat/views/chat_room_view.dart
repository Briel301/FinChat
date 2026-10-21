import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/chat_provider.dart';
import 'widgets/message_bubble_widget.dart';
import 'widgets/offline_banner_widget.dart';

/// Pantalla de Sala de Conversación 1 a 1 en Tiempo Real estilo WhatsApp.
/// Implementa scroll inverso ergonómico (`reverse: true`), barra de entrada tipo píldora,
/// renderizado optimista instantáneo y liberación de canal WebSocket al salir.
class ChatRoomView extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String otherUsername;
  final String? otherFullName;
  final String? otherAvatarUrl;

  const ChatRoomView({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUsername,
    this.otherFullName,
    this.otherAvatarUrl,
  });

  @override
  State<ChatRoomView> createState() => _ChatRoomViewState();
}

class _ChatRoomViewState extends State<ChatRoomView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_handleTextChange);

    // Ingresar a la sala y conectar suscripción Realtime tras construir el árbol
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ChatProvider>().enterChat(widget.chatId);
      }
    });
  }

  void _handleTextChange() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _isComposing) {
      setState(() {
        _isComposing = hasText;
      });
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_handleTextChange);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    setState(() {
      _isComposing = false;
    });

    // Envío reactivo y optimista (latencia 0 ms en pantalla)
    context.read<ChatProvider>().sendTextMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final chatColors = context.chatColors;
    final chatProvider = context.watch<ChatProvider>();
    final messages = chatProvider.currentMessages;
    final displayName = widget.otherFullName?.trim().isNotEmpty == true
        ? widget.otherFullName!
        : '@${widget.otherUsername}';

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // Desconectar el canal Realtime al salir de la sala
          context.read<ChatProvider>().leaveChat();
        }
      },
      child: Scaffold(
        backgroundColor: chatColors.wallpaper,
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              context.read<ChatProvider>().leaveChat();
              Navigator.of(context).pop();
            },
          ),
          title: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: Colors.white24,
                backgroundImage: widget.otherAvatarUrl != null
                    ? NetworkImage(widget.otherAvatarUrl!)
                    : null,
                child: widget.otherAvatarUrl == null
                    ? Text(
                        widget.otherUsername.isNotEmpty
                            ? widget.otherUsername[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.online,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'En línea',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.videocam_outlined),
              tooltip: 'Videollamada',
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.call_outlined),
              tooltip: 'Llamada de voz',
              onPressed: () {},
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'info', child: Text('Info. del contacto')),
                const PopupMenuItem(value: 'clear', child: Text('Vaciar chat')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            const OfflineBannerWidget(),
            // Área de Mensajes con Scroll Inverso fluido (reverse: true)
            Expanded(
              child: chatProvider.isLoadingHistory && messages.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : messages.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            // En reverse: true el índice 0 corresponde al mensaje más reciente
                            final messageIndex = messages.length - 1 - index;
                            final message = messages[messageIndex];
                            final isMine = message.isMine(chatProvider.currentUserId);

                            return MessageBubbleWidget(
                              key: ValueKey(message.id),
                              message: message,
                              isMine: isMine,
                              onRetry: () => chatProvider.retryMessage(message.id),
                            );
                          },
                        ),
            ),

            // Barra inferior ergonómica de entrada de texto
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  /// Aviso de cifrado y estado inicial vacío
  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: context.chatColors.systemBubble,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textSecondaryLight),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Los mensajes están cifrados de extremo a extremo. Nadie fuera de este chat puede leerlos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.chatColors.systemText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Barra de entrada multilínea tipo píldora adaptada a teclado
  Widget _buildInputBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Campo de texto tipo píldora
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDarkHigh : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.grey),
                      splashRadius: 20,
                      onPressed: () {},
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        minLines: 1,
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(
                          fontSize: 15.5,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Mensaje',
                          hintStyle: TextStyle(color: Colors.grey, fontSize: 15.5),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                          isDense: true,
                        ),
                        onSubmitted: (_) {
                          if (_isComposing) _handleSendMessage();
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.attach_file_rounded, color: Colors.grey),
                      splashRadius: 20,
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt_outlined, color: Colors.grey),
                      splashRadius: 20,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Botón circular de envío (animado / reactivo según texto)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _isComposing ? AppColors.tealDark : AppColors.tealAccent,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1.5)),
                ],
              ),
              child: IconButton(
                icon: Icon(
                  _isComposing ? Icons.send_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: _isComposing ? _handleSendMessage : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
