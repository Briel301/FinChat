import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../services/direct_chat_repository.dart';

/// Pantalla de conversación privada 1:1 en tiempo real con un usuario específico.
class RealChatScreen extends StatefulWidget {
  final String currentUserName;
  final String recipientName;

  const RealChatScreen({
    super.key,
    required this.currentUserName,
    required this.recipientName,
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

  late String _currentUserName;
  bool _isLoadingMessages = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _currentUserName = widget.currentUserName;
    _initChat();
  }

  /// Se ejecuta también en Hot Reload para asegurar que el canal y timer estén activos
  @override
  void reassemble() {
    super.reassemble();
    _initChat();
  }

  void _initChat() {
    if (_currentUserName.isEmpty) {
      _loadUserName();
    }
    _fetchMessages();
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

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('chat_username');
    if (savedName != null && savedName.trim().isNotEmpty && mounted) {
      setState(() {
        _currentUserName = savedName.trim();
      });
      _fetchMessages();
    }
  }

  void _startBackgroundSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _fetchMessages();
    });
  }

  Future<void> _fetchMessages() async {
    if (_currentUserName.isEmpty) return;

    try {
      final fetchedList = await DirectChatRepository.instance.fetchDirectMessages(
        currentUser: _currentUserName,
        otherUser: widget.recipientName,
      );

      if (!mounted) return;

      // Comprobar si hay cambios reales para no reconstruir ni mover el scroll innecesariamente
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
                      normalized,
                      _currentUserName,
                      widget.recipientName,
                    )) {
                  _addOrUpdateMessage(normalized);
                }
              }
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

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending || _currentUserName.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    _textController.clear();

    try {
      final inserted = await DirectChatRepository.instance.sendDirectMessage(
        sender: _currentUserName,
        receiver: widget.recipientName,
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

  String _formatTimestamp(String? isoString) {
    if (isoString == null) return '';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      return DateFormat('hh:mm a').format(dateTime);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipientInitial = widget.recipientName.isNotEmpty
        ? widget.recipientName[0].toUpperCase()
        : '?';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              child: Text(
                recipientInitial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.recipientName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const Row(
                    children: [
                      Icon(Icons.lock_outline, size: 11, color: Colors.greenAccent),
                      SizedBox(width: 4),
                      Text(
                        'Chat 1:1 en tiempo real',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
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
            icon: const Icon(Icons.refresh),
            tooltip: 'Sincronizar mensajes',
            onPressed: _fetchMessages,
          ),
        ],
      ),
      body: Column(
        children: [
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
                                      Icon(
                                        Icons.mark_chat_unread_outlined,
                                        size: 64,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Conversación 1:1 con ${widget.recipientName}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Envía un mensaje directo para iniciar el chat privado.',
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
                              final sender = (msg['sender_name'] ?? 'Anónimo').toString();
                              final content = (msg['content'] ?? '').toString();
                              final timestamp = _formatTimestamp(msg['created_at']?.toString());
                              final isMe = sender.trim().toLowerCase() ==
                                  _currentUserName.trim().toLowerCase();

                              return Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
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
                                      Text(
                                        content,
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: isMe
                                              ? Colors.white
                                              : Theme.of(context).textTheme.bodyLarge?.color,
                                        ),
                                      ),
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

          // Barra inferior de entrada de texto
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Mensaje para ${widget.recipientName}...',
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
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: _isSending
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
