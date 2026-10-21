import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../users/providers/user_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/views/chat_room_view.dart';

/// Vista interactiva para probar la búsqueda de usuarios mediante coincidencia exacta
/// de "Nombre de Usuario" utilizando [UserProvider].
class DirectorySearchView extends StatefulWidget {
  const DirectorySearchView({super.key});

  @override
  State<DirectorySearchView> createState() => _DirectorySearchViewState();
}

class _DirectorySearchViewState extends State<DirectorySearchView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(UserProvider userProvider) {
    userProvider.searchUser(_searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final isSearching = userProvider.isSearching;
    final hasSearched = userProvider.hasSearched;
    final matchedUser = userProvider.searchResult;
    final demoUsers = userProvider.demoUsers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Directorio & Búsqueda Exacta (Fase 2)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner de Requerimiento MoSCoW
            Card(
              color: Colors.amber.shade50,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.person_search, color: Colors.amber),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Must Have (10 pts): Búsqueda de usuarios mediante coincidencia EXACTA de "Nombre de Usuario" (índice B-Tree en Supabase, sin comodines %).',
                        style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Chips con nombres de prueba para testear rápido
            const Text(
              'Usuarios de prueba en Supabase (toca uno para probar):',
              style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: demoUsers.map((user) {
                return ActionChip(
                  avatar: const Icon(Icons.alternate_email, size: 16),
                  label: Text(user.username),
                  onPressed: () {
                    _searchController.text = user.username;
                    _onSearch(userProvider);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Campo de búsqueda con botón de lupa
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Nombre de usuario exacto (@usuario)',
                      hintText: 'ej. usuario1',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                userProvider.clearSearch();
                              },
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _onSearch(userProvider),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(100, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: isSearching ? null : () => _onSearch(userProvider),
                  icon: isSearching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: const Text('Buscar'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Resultado de la búsqueda exacta
            if (hasSearched) ...[
              if (matchedUser != null) ...[
                const Text(
                  'Resultado Encontrado (Coincidencia Exacta):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                              backgroundImage: matchedUser.avatarUrl != null
                                  ? NetworkImage(matchedUser.avatarUrl!)
                                  : null,
                              child: matchedUser.avatarUrl == null
                                  ? Text(
                                      matchedUser.username.isNotEmpty
                                          ? matchedUser.username[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryColor,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    matchedUser.fullName,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '@${matchedUser.username}',
                                    style: const TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    matchedUser.bio != null && matchedUser.bio!.isNotEmpty
                                        ? matchedUser.bio!
                                        : 'Sin biografía disponible',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 28),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatRoomView(
                                  chatId: 'chat_${matchedUser.id}',
                                  otherUserId: matchedUser.id,
                                  otherUsername: matchedUser.username,
                                  otherFullName: matchedUser.fullName,
                                  otherAvatarUrl: matchedUser.avatarUrl,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: Text('Iniciar Conversación con @${matchedUser.username}'),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.person_off_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 10),
                      const Text(
                        'No se encontró ningún usuario',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'La búsqueda en FinChat requiere el nombre de usuario exacto (ej. "usuario1" y no "usuario"). No se utilizan comodines %.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
