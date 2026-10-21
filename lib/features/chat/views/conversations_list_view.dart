import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/optimization_utils.dart';
import '../../ui_showcase/views/directory_search_view.dart';
import '../../users/providers/user_provider.dart';
import '../models/conversation_summary.dart';
import '../providers/chat_provider.dart';
import 'chat_room_view.dart';
import 'widgets/offline_banner_widget.dart';

/// Bandeja de entrada principal de FinChat (Inbox).
/// Muestra la lista de conversaciones 1 a 1 ordenadas por última interacción,
/// avatares de contacto, timestamps formateados, insignias de no leídos y
/// botón de acción flotante (FAB) para iniciar nuevas conversaciones.
class ConversationsListView extends StatefulWidget {
  const ConversationsListView({super.key});

  @override
  State<ConversationsListView> createState() => _ConversationsListViewState();
}

class _ConversationsListViewState extends State<ConversationsListView> {
  @override
  void initState() {
    super.initState();
    // Cargar conversaciones al abrir la vista
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ChatProvider>().loadConversations();
      }
    });
  }

  void _openSearchDirectory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DirectorySearchView(),
      ),
    );
  }

  void _navigateToChatRoom(ConversationSummary conversation) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomView(
          chatId: conversation.chatId,
          otherUserId: conversation.otherUserId,
          otherUsername: conversation.otherUsername,
          otherFullName: conversation.otherFullName,
          otherAvatarUrl: conversation.otherAvatarUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final userProvider = context.watch<UserProvider>();
    final currentUser = userProvider.currentUserProfile;
    final conversations = chatProvider.conversations;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'FinChat',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 21,
            letterSpacing: 0.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Buscar por usuario (Fase 2)',
            onPressed: _openSearchDirectory,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14, left: 4),
            child: Center(
              child: CircleAvatar(
                radius: 17,
                backgroundColor: Colors.white24,
                backgroundImage: currentUser?.avatarUrl != null
                    ? NetworkImage(currentUser!.avatarUrl!)
                    : null,
                child: currentUser?.avatarUrl == null
                    ? Text(
                        (currentUser?.username.isNotEmpty == true)
                            ? currentUser!.username[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        tooltip: 'Iniciar nuevo chat',
        onPressed: _openSearchDirectory,
        child: const Icon(Icons.chat_rounded, size: 24),
      ),
      body: Column(
        children: [
          const OfflineBannerWidget(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => context.read<ChatProvider>().loadConversations(),
              color: AppColors.teal,
              child: chatProvider.isLoadingConversations && conversations.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : conversations.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: conversations.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            indent: 80,
                            endIndent: 16,
                            color: isDark ? AppColors.outlineDark : AppColors.outlineLight,
                          ),
                          itemBuilder: (context, index) {
                            final conv = conversations[index];
                            return _buildConversationTile(conv, isDark);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  /// Elemento individual de conversación tipo ListTile WhatsApp
  Widget _buildConversationTile(ConversationSummary conv, bool isDark) {
    final titleText = conv.otherFullName?.trim().isNotEmpty == true
        ? conv.otherFullName!
        : '@${conv.otherUsername}';

    final hasUnread = conv.unreadCount > 0;
    final timeColor = hasUnread
        ? AppColors.teal
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);

    return InkWell(
      onTap: () => _navigateToChatRoom(conv),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Avatar circular del interlocutor
            CircleAvatar(
              radius: 26,
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
              backgroundImage: conv.otherAvatarUrl != null
                  ? NetworkImage(conv.otherAvatarUrl!)
                  : null,
              child: conv.otherAvatarUrl == null
                  ? Text(
                      conv.otherUsername.isNotEmpty
                          ? conv.otherUsername[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),

            // Nombre y último mensaje
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    conv.lastMessageContent,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Marca de tiempo e indicador de mensajes no leídos
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  OptimizationUtils.formatChatTimestamp(conv.lastMessageTime),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                    color: timeColor,
                  ),
                ),
                const SizedBox(height: 5),
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: const BoxDecoration(
                      color: AppColors.teal,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    child: Center(
                      child: Text(
                        conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Estado vacío amigable cuando no hay conversaciones
  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 64,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Aún no tienes conversaciones',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Conéctate con otros usuarios buscando su @nombre de usuario exacto para enviar y recibir mensajes en tiempo real.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openSearchDirectory,
              icon: const Icon(Icons.person_search_rounded),
              label: const Text('Buscar usuarios por Username'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
