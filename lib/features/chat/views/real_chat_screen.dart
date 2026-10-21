import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../ui_showcase/views/showcase_home_view.dart';

class RealChatScreen extends StatefulWidget {
  const RealChatScreen({super.key});

  @override
  State<RealChatScreen> createState() => _RealChatScreenState();
}

class _RealChatScreenState extends State<RealChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _realtimeChannel;
  Timer? _syncTimer;

  String _currentUserName = '';
  bool _isLoadingUser = true;
  bool _isLoadingMessages = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  /// Se ejecuta también en Hot Reload para asegurar que el canal y timer estén activos
  @override
  void reassemble() {
    super.reassemble();
    _initChat();
  }

  void _initChat() {
    _loadUserName();
    _fetchMessages(isInitial: _messages.isEmpty);
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
      _fetchMessages(isInitial: false);
    });
  }

  Future<void> _fetchMessages({bool isInitial = false}) async {
    try {
      final data = await SupabaseConfig.client
          .from('messages')
          .select()
          .order('id', ascending: true);

      if (!mounted) return;

      final fetchedList = List<Map<String, dynamic>>.from(data);

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
      debugPrint('[RealChatScreen] Error al sincronizar mensajes: $e');
      if (mounted && _isLoadingMessages) {
        setState(() {
          _isLoadingMessages = false;
        });
      }
    }
  }

  void _subscribeToRealtime() {
    _realtimeChannel?.unsubscribe();
    final channelName = 'messages_live_${DateTime.now().millisecondsSinceEpoch}';
    _realtimeChannel = SupabaseConfig.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.insert) {
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty) {
                _addOrUpdateMessage(newRecord);
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
        // Asegurar orden por id
        _messages.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      });
      _scrollToBottom();
    }
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('chat_username');

    if (savedName != null && savedName.trim().isNotEmpty) {
      if (mounted) {
        setState(() {
          _currentUserName = savedName.trim();
          _isLoadingUser = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingUser = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_currentUserName.isEmpty && mounted) {
          _promptForUserName(canCancel: false);
        }
      });
    }
  }

  Future<void> _promptForUserName({bool canCancel = true}) async {
    final controller = TextEditingController(text: _currentUserName);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: canCancel,
      builder: (ctx) {
        return PopScope(
          canPop: canCancel,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.person, color: AppTheme.primaryColor),
                SizedBox(width: 8),
                Text('¿Cómo te llamas?'),
              ],
            ),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Ej. Juan, María, Dispositivo 1...',
                  labelText: 'Tu apodo o nombre',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Por favor ingresa un nombre';
                  }
                  return null;
                },
              ),
            ),
            actions: [
              if (canCancel)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState?.validate() ?? false) {
                    final newName = controller.text.trim();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('chat_username', newName);
                    if (mounted) {
                      setState(() {
                        _currentUserName = newName;
                      });
                    }
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
        );
      },
    );
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
    if (text.isEmpty || _isSending) return;

    if (_currentUserName.isEmpty) {
      await _promptForUserName(canCancel: false);
      if (_currentUserName.isEmpty) return;
    }

    setState(() {
      _isSending = true;
    });

    _textController.clear();

    try {
      final inserted = await SupabaseConfig.client.from('messages').insert({
        'sender_name': _currentUserName,
        'content': text,
      }).select().single();

      _addOrUpdateMessage(inserted);
    } catch (e) {
      debugPrint('[RealChatScreen] Error al enviar mensaje: $e');
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
    if (_isLoadingUser) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FinChat Realtime',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _currentUserName.isNotEmpty ? 'Tú: $_currentUserName' : 'Sin nombre',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar mensajes',
            onPressed: () => _fetchMessages(isInitial: false),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Cambiar nombre',
            onPressed: () => _promptForUserName(canCancel: true),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'showcase') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ShowcaseHomeView()),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'showcase',
                child: Row(
                  children: [
                    Icon(Icons.dashboard_outlined, size: 20, color: Colors.blueGrey),
                    SizedBox(width: 8),
                    Text('Panel de Requerimientos'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoadingMessages
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _fetchMessages(isInitial: false),
                    child: _messages.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.chat_bubble_outline,
                                        size: 64, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'No hay mensajes aún',
                                      style: TextStyle(fontSize: 16, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      '¡Envía un mensaje para comenzar la conversación!',
                                      style: TextStyle(fontSize: 13, color: Colors.grey),
                                    ),
                                  ],
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
                                      if (!isMe)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 4),
                                          child: Text(
                                            sender,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: Colors.indigo.shade300,
                                            ),
                                          ),
                                        ),
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
                        hintText: 'Escribe un mensaje...',
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
