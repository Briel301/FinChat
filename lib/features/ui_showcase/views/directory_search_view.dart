import 'package:flutter/material.dart';
import '../../users/models/user_profile.dart';
import '../../users/services/user_service.dart';
import '../../../core/theme/app_theme.dart';
import 'chat_playground_view.dart';

/// Vista interactiva para probar la búsqueda de usuarios mediante coincidencia exacta de "Nombre de Usuario".
class DirectorySearchView extends StatefulWidget {
  const DirectorySearchView({super.key});

  @override
  State<DirectorySearchView> createState() => _DirectorySearchViewState();
}

class _DirectorySearchViewState extends State<DirectorySearchView> {
  final _userService = UserService();
  final _searchController = TextEditingController();

  UserProfile? _matchedUser;
  bool _hasSearched = false;
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performExactSearch() async {
    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _matchedUser = null;
    });

    final result = await _userService.searchByExactUsername(_searchController.text);

    setState(() {
      _isSearching = false;
      _matchedUser = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final demoUsers = _userService.getAllUsersForDemo();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Búsqueda Exacta de Usuario'),
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
                        'Must Have (10 pts): Búsqueda de usuarios mediante coincidencia EXACTA de "Nombre de Usuario" (índice B-Tree en Supabase).',
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
              'Usuarios registrados de prueba (toca uno para probar):',
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
                    _performExactSearch();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Campo de búsqueda
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Nombre de usuario exacto',
                      hintText: 'ej. usuario1',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _hasSearched = false;
                                  _matchedUser = null;
                                });
                              },
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _performExactSearch(),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(60, 50),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: _isSearching ? null : _performExactSearch,
                  child: _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Buscar'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Resultado de la búsqueda exacta
            if (_hasSearched) ...[
              if (_matchedUser != null) ...[
                const Text(
                  'Resultado Encontrado (Coincidencia Exacta):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: AppTheme.primaryColor.withOpacity(0.15),
                              child: Text(
                                _matchedUser!.username.substring(0, 1).toUpperCase(),
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _matchedUser!.fullName,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '@${_matchedUser!.username}',
                                    style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _matchedUser!.bio ?? 'Sin biografía',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ChatPlaygroundView(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: Text('Iniciar Conversación con @${_matchedUser!.username}'),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.person_off_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      const Text(
                        'No se encontró ningún usuario',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Recuerda que la búsqueda requiere el nombre exacto (ej. "usuario1" y no "usuario").',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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
