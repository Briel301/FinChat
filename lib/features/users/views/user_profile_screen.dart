import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../chat/services/direct_chat_repository.dart';

/// Widget reutilizable para mostrar el avatar de un usuario (imagen remota en Supabase Storage
/// o inicial con color determinista como respaldo).
class UserAvatarWidget extends StatelessWidget {
  final String userId;
  final String username;
  final String? avatarUrl;
  final double radius;
  final VoidCallback? onTap;

  const UserAvatarWidget({
    super.key,
    required this.userId,
    required this.username,
    this.avatarUrl,
    this.radius = 24,
    this.onTap,
  });

  static Color colorForUser(String key) {
    final colors = [
      const Color(0xFF00796B),
      const Color(0xFF1976D2),
      const Color(0xFF7B1FA2),
      const Color(0xFFC2185B),
      const Color(0xFFE64A19),
      const Color(0xFF388E3C),
      const Color(0xFF5D4037),
      const Color(0xFF455A64),
    ];
    if (key.isEmpty) return AppTheme.primaryColor;
    final hash = key.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final initial = username.trim().isNotEmpty ? username.trim()[0].toUpperCase() : '?';
    final bgColor = colorForUser(userId.isNotEmpty ? userId : username);
    final cleanUrl = avatarUrl?.trim();

    Widget avatarContent;
    if (cleanUrl != null && cleanUrl.isNotEmpty) {
      avatarContent = ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: Image.network(
            cleanUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackInitial(initial, bgColor),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: bgColor,
                alignment: Alignment.center,
                child: SizedBox(
                  width: radius * 0.8,
                  height: radius * 0.8,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else {
      avatarContent = _buildFallbackInitial(initial, bgColor);
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatarContent,
      );
    }
    return avatarContent;
  }

  Widget _buildFallbackInitial(String initial, Color bgColor) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.78,
        ),
      ),
    );
  }
}

/// Pantalla dedicada para gestionar el perfil del usuario actual:
/// subida de Avatar (Galería o Cámara) e información básica (`username`, `full_name`, `bio`, `UUID`).
class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String initialUsername;
  final bool isFirstSetup;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.initialUsername,
    this.isFirstSetup = false,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _fullNameController;
  late final TextEditingController _bioController;

  String? _avatarUrl;
  bool _isLoadingProfile = true;
  bool _isUploadingAvatar = false;
  bool _isSaving = false;

  static const List<String> _presetBios = [
    '¡Hola! Estoy usando FinChat.',
    'Disponible',
    'Ocupado',
    'En la escuela / universidad',
    'En el trabajo',
    'Solo urgencias',
  ];

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.initialUsername);
    _fullNameController = TextEditingController();
    _bioController = TextEditingController(text: DirectChatRepository.defaultBio);
    _loadCurrentProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentProfile() async {
    final localName = await DirectChatRepository.instance.getLocalUserName();
    final localFullName = await DirectChatRepository.instance.getLocalFullName();
    final localBio = await DirectChatRepository.instance.getLocalBio();
    final localAvatar = await DirectChatRepository.instance.getLocalAvatarUrl();

    if (mounted) {
      setState(() {
        if (localName.isNotEmpty) _usernameController.text = localName;
        if (localFullName.isNotEmpty) _fullNameController.text = localFullName;
        if (localBio.isNotEmpty) _bioController.text = localBio;
        _avatarUrl = localAvatar;
      });
    }

    // Consultar Supabase para sincronizar datos remotos más recientes
    final remote = await DirectChatRepository.instance.fetchUserProfile(
      widget.userId,
      syncLocalIfCurrentUser: true,
    );

    if (mounted) {
      setState(() {
        if (remote != null) {
          final rUser = (remote['username'] ?? '').toString().trim();
          final rFull = (remote['full_name'] ?? '').toString().trim();
          final rBio = (remote['bio'] ?? '').toString().trim();
          final rAvatar = (remote['avatar_url'] ?? '').toString().trim();

          if (rUser.isNotEmpty) _usernameController.text = rUser;
          if (rFull.isNotEmpty) _fullNameController.text = rFull;
          if (rBio.isNotEmpty) _bioController.text = rBio;
          if (rAvatar.isNotEmpty) _avatarUrl = rAvatar;
        }
        _isLoadingProfile = false;
      });
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    if (_isUploadingAvatar) return;

    try {
      final XFile? picked = await DirectChatRepository.instance.pickOrCaptureImage(source);
      if (picked == null || !mounted) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      setState(() {
        _isUploadingAvatar = true;
      });

      final effectiveName = _usernameController.text.trim().isNotEmpty
          ? _usernameController.text.trim()
          : 'Usuario';

      final uploadedUrl = await DirectChatRepository.instance.uploadUserAvatar(
        userId: widget.userId,
        username: effectiveName,
        bytes: bytes,
        fileName: picked.name.isNotEmpty ? picked.name : 'avatar.jpg',
      );

      if (mounted) {
        setState(() {
          _avatarUrl = uploadedUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto de perfil actualizada correctamente'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar el avatar: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAvatar = false;
        });
      }
    }
  }

  void _showAvatarSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Foto de Perfil',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppTheme.primaryColor,
                    child: Icon(Icons.photo_library_outlined, color: Colors.white),
                  ),
                  title: const Text('Seleccionar de la Galería'),
                  subtitle: const Text('Elegir una imagen almacenada en tu dispositivo'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickAndUploadAvatar(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppTheme.accentColor,
                    child: Icon(Icons.camera_alt_outlined, color: Colors.white),
                  ),
                  title: const Text('Tomar fotografía con la Cámara'),
                  subtitle: const Text('Capturar una foto nueva ahora mismo'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickAndUploadAvatar(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false) || _isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final username = _usernameController.text.trim();
      final fullName = _fullNameController.text.trim();
      final bio = _bioController.text.trim().isNotEmpty
          ? _bioController.text.trim()
          : DirectChatRepository.defaultBio;

      await DirectChatRepository.instance.registerOrUpdateUser(
        userId: widget.userId,
        username: username,
        fullName: fullName,
        bio: bio,
        avatarUrl: _avatarUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil guardado y sincronizado en tiempo real'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar el perfil: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewName = _usernameController.text.trim().isNotEmpty
        ? _usernameController.text.trim()
        : 'Usuario';

    return PopScope(
      canPop: !widget.isFirstSetup,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.isFirstSetup,
          title: Text(widget.isFirstSetup ? 'Configura tu Perfil' : 'Mi Perfil de Usuario'),
          actions: [
            if (!widget.isFirstSetup)
              IconButton(
                icon: const Icon(Icons.check),
                tooltip: 'Guardar cambios',
                onPressed: (_isSaving || _isUploadingAvatar) ? null : _saveProfile,
              ),
          ],
        ),
        body: _isLoadingProfile
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Sección de Avatar con botón de cámara superpuesto
                      Center(
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.4),
                                  width: 3,
                                ),
                              ),
                              child: UserAvatarWidget(
                                userId: widget.userId,
                                username: previewName,
                                avatarUrl: _avatarUrl,
                                radius: 58,
                                onTap: _showAvatarSourceSheet,
                              ),
                            ),
                            if (_isUploadingAvatar)
                              Positioned.fill(
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: const CircularProgressIndicator(color: Colors.white),
                                ),
                              ),
                            Material(
                              color: AppTheme.primaryColor,
                              shape: const CircleBorder(),
                              elevation: 4,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _isUploadingAvatar ? null : _showAvatarSourceSheet,
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _isUploadingAvatar ? null : _showAvatarSourceSheet,
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                        label: const Text('Cambiar foto de perfil'),
                      ),
                      const SizedBox(height: 16),

                      // Campo 1: Nombre de usuario / Apodo visible (Obligatorio)
                      TextFormField(
                        controller: _usernameController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Nombre de usuario (Apodo visible) *',
                          hintText: 'Ej. Briel, Maria, Juan...',
                          prefixIcon: Icon(Icons.alternate_email),
                          helperText: 'Nombre principal con el que te verán en tus chats',
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Por favor ingresa un nombre de usuario';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // Campo 2: Nombre Completo (Información básica)
                      TextFormField(
                        controller: _fullNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nombre completo (Opcional)',
                          hintText: 'Ej. Gabriel Alejandro',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Campo 3: Biografía / Estado del usuario
                      TextFormField(
                        controller: _bioController,
                        maxLines: 2,
                        maxLength: 120,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Información / Estado',
                          hintText: 'Escribe un estado o información para tu perfil...',
                          prefixIcon: Icon(Icons.info_outline),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Chips rápidos de estado
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Estados rápidos:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: _presetBios.map((preset) {
                            return ActionChip(
                              label: Text(preset, style: const TextStyle(fontSize: 12)),
                              onPressed: () {
                                setState(() {
                                  _bioController.text = preset;
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Tarjeta de Identidad Inmutable (UUID)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade900
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.fingerprint, color: AppTheme.primaryColor, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ID Único de Usuario (Inmutable)',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.userId,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: 'Copiar ID',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: widget.userId));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('ID único copiado al portapapeles'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Botón Guardar
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: (_isSaving || _isUploadingAvatar) ? null : _saveProfile,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _isSaving ? 'Guardando...' : 'Guardar Perfil',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Modal para visualizar la información básica y el avatar de un contacto.
class ContactProfileSheet extends StatelessWidget {
  final String userId;
  final String username;
  final String fullName;
  final String? bio;
  final String? avatarUrl;

  const ContactProfileSheet({
    super.key,
    required this.userId,
    required this.username,
    this.fullName = '',
    this.bio,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBio = (bio != null && bio!.trim().isNotEmpty)
        ? bio!.trim()
        : DirectChatRepository.defaultBio;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            UserAvatarWidget(
              userId: userId,
              username: username,
              avatarUrl: avatarUrl,
              radius: 52,
            ),
            const SizedBox(height: 14),
            Text(
              username,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            if (fullName.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                fullName.trim(),
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade900
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Información / Estado',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    effectiveBio,
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.verified_user_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  'ID: ${userId.length > 12 ? "${userId.substring(0, 12)}..." : userId}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
