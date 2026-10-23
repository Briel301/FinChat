import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../ui_showcase/views/showcase_home_view.dart';
import '../services/direct_chat_repository.dart';
import 'real_chat_screen.dart';

/// Pantalla principal de directorio y conversaciones 1:1 basadas en ID único inmutable (`user_id`).
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<DirectChatContact> _contacts = [];
  RealtimeChannel? _realtimeChannel;
  Timer? _syncTimer;

  String _currentUserId = '';
  String _currentUserName = '';
  String _searchQuery = '';
  bool _isLoadingUser = true;
  bool _isLoadingContacts = true;

  @override
  void initState() {
    super.initState();
    _initDirectory();
  }

  @override
  void reassemble() {
    super.reassemble();
    _initDirectory();
  }

  Future<void> _initDirectory() async {
    await _loadUserIdentity();
    if (_currentUserId.isNotEmpty && _currentUserName.isNotEmpty) {
      await DirectChatRepository.instance.registerOrUpdateUser(
        userId: _currentUserId,
        username: _currentUserName,
      );
      await _fetchContacts();
    }
    _subscribeToRealtime();
    _startBackgroundSync();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _searchController.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _startBackgroundSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_currentUserId.isNotEmpty && _currentUserName.isNotEmpty) {
        _fetchContacts();
      }
    });
  }

  void _subscribeToRealtime() {
    _realtimeChannel?.unsubscribe();
    final channelName = 'directory_live_${DateTime.now().millisecondsSinceEpoch}';
    _realtimeChannel = SupabaseConfig.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: SupabaseConfig.tableMessages,
          callback: (_) {
            if (_currentUserId.isNotEmpty && _currentUserName.isNotEmpty) {
              _fetchContacts();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: SupabaseConfig.tableProfiles,
          callback: (_) {
            if (_currentUserId.isNotEmpty && _currentUserName.isNotEmpty) {
              _fetchContacts();
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadUserIdentity() async {
    final userId = await DirectChatRepository.instance.ensureLocalUserId();
    final savedName = await DirectChatRepository.instance.getLocalUserName();

    if (savedName.isNotEmpty) {
      if (mounted) {
        setState(() {
          _currentUserId = userId;
          _currentUserName = savedName;
          _isLoadingUser = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _currentUserId = userId;
          _isLoadingUser = false;
          _isLoadingContacts = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_currentUserName.isEmpty && mounted) {
          _promptForUserName(canCancel: false);
        }
      });
    }
  }

  Future<void> _fetchContacts() async {
    if (_currentUserId.isEmpty || _currentUserName.isEmpty) return;

    try {
      final fetched = await DirectChatRepository.instance.fetchContactsWithLastMessage(
        currentUserId: _currentUserId,
        currentUserName: _currentUserName,
      );

      if (!mounted) return;
      setState(() {
        _contacts = fetched;
        _isLoadingContacts = false;
      });
    } catch (e) {
      debugPrint('[ChatListScreen] Error al cargar contactos: $e');
      if (mounted && _isLoadingContacts) {
        setState(() {
          _isLoadingContacts = false;
        });
      }
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
                Text('Tu Perfil de Usuario'),
              ],
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Ej. Juan, María, Briel...',
                      labelText: 'Tu nombre visible',
                      helperText: 'Puedes cambiarlo cuando quieras sin perder tus chats',
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Por favor ingresa tu nombre de usuario';
                      }
                      return null;
                    },
                  ),
                  if (_currentUserId.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'ID único: ${_currentUserId.substring(0, 8)}...',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ],
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
                    if (mounted) {
                      setState(() {
                        _currentUserName = newName;
                      });
                    }
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    await DirectChatRepository.instance.registerOrUpdateUser(
                      userId: _currentUserId,
                      username: newName,
                    );
                    await _fetchContacts();
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

  Future<void> _promptNewDirectChat() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? errorText;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.person_add_alt_1, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text('Buscar Usuario'),
                ],
              ),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Nombre del usuario registrado...',
                    labelText: '¿Con quién deseas chatear?',
                    errorText: errorText,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Ingresa el nombre del usuario';
                    }
                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() ?? false) {
                      final targetName = controller.text.trim();
                      final profile =
                          await DirectChatRepository.instance.findProfileByUsername(targetName);
                      if (profile == null) {
                        setDialogState(() {
                          errorText = 'Usuario "$targetName" aún no registrado';
                        });
                        return;
                      }
                      if (profile['id'] == _currentUserId) {
                        setDialogState(() {
                          errorText = 'Ese es tu propio usuario';
                        });
                        return;
                      }
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      _openChatWith(
                        recipientUserId: profile['id']!,
                        recipientName: profile['username']!,
                      );
                    }
                  },
                  child: const Text('Abrir Chat'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openChatWith({
    required String recipientUserId,
    required String recipientName,
  }) async {
    if (_currentUserName.isEmpty) {
      await _promptForUserName(canCancel: false);
      if (_currentUserName.isEmpty) return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RealChatScreen(
          currentUserId: _currentUserId,
          currentUserName: _currentUserName,
          recipientUserId: recipientUserId,
          recipientName: recipientName,
        ),
      ),
    );
    _fetchContacts();
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null) return '';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final isToday = dateTime.year == now.year &&
          dateTime.month == now.month &&
          dateTime.day == now.day;
      if (isToday) {
        return DateFormat('hh:mm a').format(dateTime);
      }
      return DateFormat('dd/MM hh:mm a').format(dateTime);
    } catch (_) {
      return '';
    }
  }

  Color _avatarColorFor(String idOrName) {
    final palette = [
      Colors.indigo,
      Colors.teal,
      Colors.deepPurple,
      Colors.blue.shade700,
      Colors.orange.shade800,
      Colors.pink.shade700,
      Colors.cyan.shade700,
    ];
    final hash = idOrName.toLowerCase().codeUnits.fold<int>(0, (p, c) => p + c);
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final filteredContacts = _contacts.where((c) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return c.username.toLowerCase().contains(q) ||
          (c.lastMessage?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FinChat 1:1',
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
                  _currentUserName.isNotEmpty
                      ? 'Conectado como: $_currentUserName'
                      : 'Sin usuario',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar usuarios',
            onPressed: _fetchContacts,
          ),
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined),
            tooltip: 'Cambiar mi nombre',
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
          // Barra de búsqueda de usuarios
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              decoration: InputDecoration(
                hintText: 'Buscar usuario o conversación...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade900
                    : Colors.grey.shade200,
              ),
            ),
          ),

          Expanded(
            child: _isLoadingContacts
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchContacts,
                    child: filteredContacts.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 32),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.people_outline,
                                        size: 64,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _searchQuery.isEmpty
                                            ? 'Aún no hay otros usuarios registrados'
                                            : 'No se encontraron usuarios para "$_searchQuery"',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'En cuanto otro dispositivo abra la aplicación, aparecerá aquí automáticamente con su ID único.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 13, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: filteredContacts.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1, indent: 72),
                            itemBuilder: (context, index) {
                              final contact = filteredContacts[index];
                              final hasMessage = contact.lastMessage != null &&
                                  contact.lastMessage!.isNotEmpty;
                              final initial = contact.username.isNotEmpty
                                  ? contact.username[0].toUpperCase()
                                  : '?';

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                leading: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: _avatarColorFor(contact.userId),
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  contact.username,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    hasMessage
                                        ? '${contact.isLastFromMe ? "Tú: " : ""}${contact.lastMessage}'
                                        : 'Toca para iniciar conversación 1:1',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontStyle: hasMessage ? FontStyle.normal : FontStyle.italic,
                                      color: hasMessage
                                          ? Theme.of(context).textTheme.bodyMedium?.color
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (contact.lastTimestamp != null)
                                      Text(
                                        _formatTimestamp(contact.lastTimestamp),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    const Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                                onTap: () => _openChatWith(
                                  recipientUserId: contact.userId,
                                  recipientName: contact.username,
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _promptNewDirectChat,
        icon: const Icon(Icons.chat),
        label: const Text('Buscar Usuario'),
      ),
    );
  }
}
