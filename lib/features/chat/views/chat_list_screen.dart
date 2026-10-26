import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../ui_showcase/views/showcase_home_view.dart';
import '../../users/views/user_profile_screen.dart';
import '../services/direct_chat_repository.dart';
import 'real_chat_screen.dart';

/// Pantalla principal de directorio y conversaciones 1:1 basadas en ID único inmutable (`user_id`),
/// con visualización de avatares e información de perfil en tiempo real.
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
  String? _currentUserAvatarUrl;
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
          callback: (payload) {
            final updated = payload.newRecord;
            if (updated['id']?.toString() == _currentUserId) {
              _refreshCurrentUserFromLocalOrRemote();
            }
            if (_currentUserId.isNotEmpty && _currentUserName.isNotEmpty) {
              _fetchContacts();
            }
          },
        )
        .subscribe();
  }

  Future<void> _refreshCurrentUserFromLocalOrRemote() async {
    final name = await DirectChatRepository.instance.getLocalUserName();
    final avatar = await DirectChatRepository.instance.getLocalAvatarUrl();
    if (mounted) {
      setState(() {
        if (name.isNotEmpty) _currentUserName = name;
        _currentUserAvatarUrl = avatar;
      });
    }
  }

  Future<void> _loadUserIdentity() async {
    final userId = await DirectChatRepository.instance.ensureLocalUserId();
    await DirectChatRepository.instance.fetchUserProfile(
      userId,
      syncLocalIfCurrentUser: true,
    );
    final savedName = await DirectChatRepository.instance.getLocalUserName();
    final savedAvatar = await DirectChatRepository.instance.getLocalAvatarUrl();

    if (savedName.isNotEmpty) {
      if (mounted) {
        setState(() {
          _currentUserId = userId;
          _currentUserName = savedName;
          _currentUserAvatarUrl = savedAvatar;
          _isLoadingUser = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _currentUserId = userId;
          _currentUserAvatarUrl = savedAvatar;
          _isLoadingUser = false;
          _isLoadingContacts = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_currentUserName.isEmpty && mounted) {
          _openMyProfileScreen(isFirstSetup: true);
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

  Future<void> _openMyProfileScreen({bool isFirstSetup = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: _currentUserId,
          initialUsername: _currentUserName,
          isFirstSetup: isFirstSetup,
        ),
      ),
    );

    final updatedName = await DirectChatRepository.instance.getLocalUserName();
    final updatedAvatar = await DirectChatRepository.instance.getLocalAvatarUrl();

    if (mounted) {
      setState(() {
        if (updatedName.isNotEmpty) _currentUserName = updatedName;
        _currentUserAvatarUrl = updatedAvatar;
      });
    }
    if (_currentUserName.isNotEmpty) {
      await _fetchContacts();
    }
  }

  void _showContactProfileSheet(DirectChatContact contact) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ContactProfileSheet(
        userId: contact.userId,
        username: contact.username,
        fullName: contact.fullName,
        bio: contact.bio,
        avatarUrl: contact.avatarUrl,
      ),
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
    String? recipientAvatarUrl,
    String? recipientBio,
    String recipientFullName = '',
  }) async {
    if (_currentUserName.isEmpty) {
      await _openMyProfileScreen(isFirstSetup: true);
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
          initialRecipientAvatarUrl: recipientAvatarUrl,
          initialRecipientBio: recipientBio,
          initialRecipientFullName: recipientFullName,
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
          c.fullName.toLowerCase().contains(q) ||
          (c.bio?.toLowerCase().contains(q) ?? false) ||
          (c.lastMessage?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: GestureDetector(
          onTap: () => _openMyProfileScreen(isFirstSetup: false),
          child: Row(
            children: [
              UserAvatarWidget(
                userId: _currentUserId,
                username: _currentUserName.isNotEmpty ? _currentUserName : '?',
                avatarUrl: _currentUserAvatarUrl,
                radius: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
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
                        Flexible(
                          child: Text(
                            _currentUserName.isNotEmpty
                                ? 'Mi perfil: $_currentUserName'
                                : 'Configurar perfil',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar usuarios',
            onPressed: _fetchContacts,
          ),
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined),
            tooltip: 'Editar mi perfil y avatar',
            onPressed: () => _openMyProfileScreen(isFirstSetup: false),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'profile') {
                _openMyProfileScreen(isFirstSetup: false);
              } else if (value == 'showcase') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ShowcaseHomeView()),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 20, color: AppTheme.primaryColor),
                    SizedBox(width: 8),
                    Text('Mi Perfil y Avatar'),
                  ],
                ),
              ),
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
                hintText: 'Buscar usuario, estado o conversación...',
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
                                        'En cuanto otro dispositivo abra la aplicación, aparecerá aquí automáticamente con su avatar y perfil.',
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
                                const Divider(height: 1, indent: 76),
                            itemBuilder: (context, index) {
                              final contact = filteredContacts[index];
                              final hasMessage = contact.lastMessage != null &&
                                  contact.lastMessage!.isNotEmpty;
                              final fallbackSubtitle = (contact.bio != null &&
                                      contact.bio!.trim().isNotEmpty)
                                  ? contact.bio!.trim()
                                  : 'Toca para iniciar conversación 1:1';

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                leading: UserAvatarWidget(
                                  userId: contact.userId,
                                  username: contact.username,
                                  avatarUrl: contact.avatarUrl,
                                  radius: 25,
                                  onTap: () => _showContactProfileSheet(contact),
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        contact.username,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    if (contact.fullName.trim().isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          '(${contact.fullName.trim()})',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    hasMessage
                                        ? '${contact.isLastFromMe ? "Tú: " : ""}${contact.lastMessage}'
                                        : fallbackSubtitle,
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
                                  recipientAvatarUrl: contact.avatarUrl,
                                  recipientBio: contact.bio,
                                  recipientFullName: contact.fullName,
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
