import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/supabase/supabase_config.dart';

/// Modelo de contacto y resumen de conversación 1:1 basado en identidad inmutable (UUID).
class DirectChatContact {
  final String userId;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final String? bio;
  final String? lastMessage;
  final String? lastMediaType;
  final String? lastTimestamp;
  final int? lastMessageId;
  final bool isLastFromMe;

  const DirectChatContact({
    required this.userId,
    required this.username,
    this.fullName = '',
    this.avatarUrl,
    this.bio,
    this.lastMessage,
    this.lastMediaType,
    this.lastTimestamp,
    this.lastMessageId,
    this.isLastFromMe = false,
  });
}

/// Repositorio para gestionar usuarios con ID único inmutable (`profiles.id`),
/// perfil con avatar e información básica, almacenamiento en Supabase Storage
/// y mensajes 1:1 vinculados por `sender_id` y `receiver_id`.
class DirectChatRepository {
  DirectChatRepository._();
  static final DirectChatRepository instance = DirectChatRepository._();

  static const String _prefUserIdKey = 'chat_user_id';
  static const String _prefUserNameKey = 'chat_username';
  static const String _prefFullNameKey = 'chat_full_name';
  static const String _prefBioKey = 'chat_bio';
  static const String _prefAvatarUrlKey = 'chat_avatar_url';
  static const String defaultBio = '¡Hola! Estoy usando FinChat.';

  static const String _presenceMarker = '__SYS_PRESENCE__';
  static final RegExp _legacyRecipientRegex = RegExp(r'^@\[([^\]]+)\]:\s*(.*)$', dotAll: true);
  static const Uuid _uuid = Uuid();
  final ImagePicker _imagePicker = ImagePicker();

  /// Obtiene o genera el UUID único e inmutable de este dispositivo/usuario.
  Future<String> ensureLocalUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? userId = prefs.getString(_prefUserIdKey);
    if (userId == null || userId.trim().isEmpty || !Uuid.isValidUUID(fromString: userId)) {
      userId = _uuid.v4();
      await prefs.setString(_prefUserIdKey, userId);
    }
    return userId;
  }

  /// Obtiene el nombre de usuario guardado localmente.
  Future<String> getLocalUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_prefUserNameKey) ?? '').trim();
  }

  /// Obtiene el nombre completo guardado localmente.
  Future<String> getLocalFullName() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_prefFullNameKey) ?? '').trim();
  }

  /// Obtiene la biografía/estado guardado localmente.
  Future<String> getLocalBio() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_prefBioKey) ?? '').trim();
    return saved.isNotEmpty ? saved : defaultBio;
  }

  /// Obtiene la URL del avatar guardada localmente.
  Future<String?> getLocalAvatarUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_prefAvatarUrlKey) ?? '').trim();
    return saved.isNotEmpty ? saved : null;
  }

  /// Consulta el perfil de un usuario en Supabase (`public.profiles`) por su `userId`.
  Future<Map<String, dynamic>?> fetchUserProfile(
    String userId, {
    bool syncLocalIfCurrentUser = false,
  }) async {
    if (userId.trim().isEmpty) return null;
    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.tableProfiles)
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data != null) {
        final map = Map<String, dynamic>.from(data);
        if (syncLocalIfCurrentUser) {
          final prefs = await SharedPreferences.getInstance();
          final uname = (map['username'] ?? '').toString().trim();
          final fname = (map['full_name'] ?? '').toString().trim();
          final bio = (map['bio'] ?? '').toString().trim();
          final avatar = (map['avatar_url'] ?? '').toString().trim();

          if (uname.isNotEmpty) await prefs.setString(_prefUserNameKey, uname);
          await prefs.setString(_prefFullNameKey, fname);
          if (bio.isNotEmpty) await prefs.setString(_prefBioKey, bio);
          if (avatar.isNotEmpty) {
            await prefs.setString(_prefAvatarUrlKey, avatar);
          }
        }
        return map;
      }
    } catch (e) {
      debugPrint('[DirectChatRepository] Error al obtener perfil de $userId: $e');
    }
    return null;
  }

  /// Guarda los datos del perfil localmente y actualiza su registro en `public.profiles`
  /// manteniendo el mismo UUID inmutable.
  Future<void> registerOrUpdateUser({
    required String userId,
    required String username,
    String? fullName,
    String? bio,
    String? avatarUrl,
  }) async {
    final cleanName = username.trim();
    if (cleanName.isEmpty || userId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUserNameKey, cleanName);
    if (fullName != null) {
      await prefs.setString(_prefFullNameKey, fullName.trim());
    }
    if (bio != null) {
      final effectiveBio = bio.trim().isNotEmpty ? bio.trim() : defaultBio;
      await prefs.setString(_prefBioKey, effectiveBio);
    }
    if (avatarUrl != null) {
      await prefs.setString(_prefAvatarUrlKey, avatarUrl.trim());
    }

    final savedFullName = fullName?.trim() ?? (prefs.getString(_prefFullNameKey) ?? '').trim();
    final savedBio = bio?.trim() ?? (prefs.getString(_prefBioKey) ?? defaultBio).trim();
    final savedAvatar = avatarUrl?.trim() ?? (prefs.getString(_prefAvatarUrlKey) ?? '').trim();

    final Map<String, dynamic> payload = {
      'id': userId,
      'username': cleanName,
      'full_name': savedFullName,
      'bio': savedBio.isNotEmpty ? savedBio : defaultBio,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (savedAvatar.isNotEmpty) {
      payload['avatar_url'] = savedAvatar;
    }

    try {
      await SupabaseConfig.client.from(SupabaseConfig.tableProfiles).upsert(
            payload,
            onConflict: 'id',
          );
    } catch (e) {
      debugPrint('[DirectChatRepository] Error al sincronizar perfil completo, reintentando campos base: $e');
      try {
        await SupabaseConfig.client.from(SupabaseConfig.tableProfiles).upsert(
          {
            'id': userId,
            'username': cleanName,
            if (savedAvatar.isNotEmpty) 'avatar_url': savedAvatar,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'id',
        );
      } catch (innerError) {
        debugPrint('[DirectChatRepository] Error al sincronizar perfil base: $innerError');
      }
    }
  }

  /// Selecciona una imagen de la galería o captura una fotografía con la cámara.
  /// En Android/iOS usa la cámara nativa; en Linux Desktop captura desde `/dev/video0` con `ffmpeg`.
  Future<XFile?> pickOrCaptureImage(ImageSource source) async {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.linux &&
        source == ImageSource.camera) {
      return _captureLinuxWebcamPhoto();
    }

    return _imagePicker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
  }

  /// Captura un fotograma desde la webcam `/dev/video0` en Linux usando `ffmpeg`.
  Future<XFile?> _captureLinuxWebcamPhoto() async {
    final tempPath =
        '${Directory.systemTemp.path}/finchat_webcam_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      final result = await Process.run('ffmpeg', [
        '-y',
        '-f',
        'v4l2',
        '-i',
        '/dev/video0',
        '-frames:v',
        '1',
        tempPath,
      ]);

      final file = File(tempPath);
      if (result.exitCode == 0 && await file.exists() && await file.length() > 0) {
        return XFile(tempPath, name: 'webcam_photo.jpg', mimeType: 'image/jpeg');
      } else {
        throw StateError(
          'No se pudo capturar desde /dev/video0 (código ${result.exitCode}). Verifica que la webcam no esté en uso por otra app.',
        );
      }
    } catch (e) {
      debugPrint('[DirectChatRepository] Error capturando webcam en Linux: $e');
      rethrow;
    }
  }

  /// Comprime bytes de imagen en Android/iOS con fallback seguro a los bytes originales en Desktop.
  Future<Uint8List> compressImageBytes(
    Uint8List rawBytes, {
    int minWidth = 1080,
    int minHeight = 1080,
    int quality = 80,
  }) async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          rawBytes,
          minWidth: minWidth,
          minHeight: minHeight,
          quality: quality,
        );
        if (compressed.isNotEmpty && compressed.length < rawBytes.length) {
          return compressed;
        }
      } catch (e) {
        debugPrint('[DirectChatRepository] Compresión nativa omitida: $e');
      }
    }
    return rawBytes;
  }

  /// Sube un archivo binario (`Uint8List`) a un bucket de Supabase Storage y retorna su URL pública.
  Future<String> uploadMediaBytes({
    required String bucket,
    required Uint8List bytes,
    required String fileName,
    String contentType = 'image/jpeg',
  }) async {
    final safeFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath = '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}_$safeFileName';

    await SupabaseConfig.storage.from(bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );

    return SupabaseConfig.storage.from(bucket).getPublicUrl(storagePath);
  }

  /// Sube una nueva imagen de avatar al bucket `avatars`, actualiza `profiles.avatar_url`
  /// y retorna la URL pública resultante.
  Future<String> uploadUserAvatar({
    required String userId,
    required String username,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final compressed = await compressImageBytes(
      bytes,
      minWidth: 512,
      minHeight: 512,
      quality: 82,
    );

    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';
    final contentType = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
            ? 'image/webp'
            : 'image/jpeg';

    final publicUrl = await uploadMediaBytes(
      bucket: SupabaseConfig.bucketAvatars,
      bytes: compressed,
      fileName: 'avatar_${userId.substring(0, 8)}.$ext',
      contentType: contentType,
    );

    await registerOrUpdateUser(
      userId: userId,
      username: username,
      avatarUrl: publicUrl,
    );

    return publicUrl;
  }

  /// Normaliza un registro de `messages`. Extrae `sender_id`, `receiver_id`, `sender_name`,
  /// `content` y metadatos multimedia (`media_url`, `media_type`, `file_size_bytes`, `duration_seconds`).
  Map<String, dynamic>? normalizeMessage(Map<String, dynamic> raw) {
    final rawContent = (raw['content'] ?? '').toString();
    if (rawContent == _presenceMarker) {
      return null;
    }

    final senderId = raw['sender_id']?.toString().trim() ?? '';
    final receiverId = raw['receiver_id']?.toString().trim() ?? '';
    final senderName = (raw['sender_name'] ?? '').toString().trim();

    String? legacyReceiverName = raw['receiver_name']?.toString().trim();
    String cleanContent = rawContent;

    final match = _legacyRecipientRegex.firstMatch(rawContent);
    if (match != null) {
      legacyReceiverName = match.group(1)?.trim();
      cleanContent = match.group(2) ?? '';
    }

    if (senderId.isEmpty && senderName.isEmpty) return null;

    final mediaUrl = raw['media_url']?.toString().trim();
    final rawMediaType = (raw['media_type'] ?? '').toString().trim().toLowerCase();
    final String mediaType;
    if (rawMediaType.isNotEmpty) {
      mediaType = rawMediaType;
    } else if (mediaUrl != null && mediaUrl.isNotEmpty) {
      mediaType = 'image';
    } else {
      mediaType = 'text';
    }

    return {
      'id': raw['id'],
      'created_at': raw['created_at'],
      'sender_id': senderId,
      'receiver_id': receiverId,
      'sender_name': senderName,
      'receiver_name': legacyReceiverName ?? '',
      'content': cleanContent,
      'media_url': (mediaUrl != null && mediaUrl.isNotEmpty) ? mediaUrl : null,
      'media_type': mediaType,
      'file_size_bytes': raw['file_size_bytes'],
      'duration_seconds': raw['duration_seconds'],
    };
  }

  /// Formatea el texto de vista previa de un mensaje para el listado de conversaciones.
  String formatMessagePreview(Map<String, dynamic>? normalizedMsg) {
    if (normalizedMsg == null) return '';
    final mediaType = (normalizedMsg['media_type'] ?? 'text').toString();
    final content = (normalizedMsg['content'] ?? '').toString().trim();

    switch (mediaType) {
      case 'image':
        return content.isNotEmpty ? '📷 Foto: $content' : '📷 Foto';
      case 'video':
        return content.isNotEmpty ? '🎥 Video: $content' : '🎥 Video';
      case 'audio':
        final dur = normalizedMsg['duration_seconds'];
        final durText = dur != null ? ' (${dur}s)' : '';
        return '🎤 Nota de voz$durText';
      default:
        return content;
    }
  }

  /// Verifica si un mensaje pertenece a la conversación 1:1 entre el usuario actual y el destinatario.
  bool isMessageBetween({
    required Map<String, dynamic> normalizedMsg,
    required String currentUserId,
    required String otherUserId,
    String? currentUserName,
    String? otherUserName,
  }) {
    final msgSenderId = (normalizedMsg['sender_id'] ?? '').toString();
    final msgReceiverId = (normalizedMsg['receiver_id'] ?? '').toString();

    if (msgSenderId.isNotEmpty &&
        msgReceiverId.isNotEmpty &&
        currentUserId.isNotEmpty &&
        otherUserId.isNotEmpty) {
      return (msgSenderId == currentUserId && msgReceiverId == otherUserId) ||
          (msgSenderId == otherUserId && msgReceiverId == currentUserId);
    }

    if (msgSenderId.isEmpty &&
        msgReceiverId.isEmpty &&
        currentUserName != null &&
        otherUserName != null) {
      final a = currentUserName.trim().toLowerCase();
      final b = otherUserName.trim().toLowerCase();
      final sName = (normalizedMsg['sender_name'] ?? '').toString().trim().toLowerCase();
      final rName = (normalizedMsg['receiver_name'] ?? '').toString().trim().toLowerCase();
      if (a.isNotEmpty && b.isNotEmpty) {
        return (sName == a && rName == b) || (sName == b && rName == a);
      }
    }

    return false;
  }

  /// Busca o resuelve un perfil por su nombre de usuario en `profiles`.
  Future<Map<String, String>?> findProfileByUsername(String username) async {
    final clean = username.trim();
    if (clean.isEmpty) return null;

    try {
      final data = await SupabaseConfig.client
          .from(SupabaseConfig.tableProfiles)
          .select('id, username')
          .ilike('username', clean)
          .limit(1);

      final list = data as List;
      if (list.isNotEmpty) {
        final row = list.first;
        return {
          'id': row['id'].toString(),
          'username': row['username'].toString(),
        };
      }
    } catch (e) {
      debugPrint('[DirectChatRepository] Error buscando perfil por username: $e');
    }
    return null;
  }

  /// Obtiene la lista de usuarios registrados en `profiles` (excluyendo `currentUserId`)
  /// junto con su avatar, información básica y el último mensaje intercambiado por `userId`.
  Future<List<DirectChatContact>> fetchContactsWithLastMessage({
    required String currentUserId,
    required String currentUserName,
  }) async {
    final Map<String, Map<String, String?>> profilesById = {};
    final Map<String, String> userIdByLowerName = {};

    try {
      final profilesData = await SupabaseConfig.client
          .from(SupabaseConfig.tableProfiles)
          .select()
          .order('username', ascending: true);

      for (final row in (profilesData as List)) {
        final id = (row['id'] ?? '').toString().trim();
        final uname = (row['username'] ?? '').toString().trim();
        final fullName = (row['full_name'] ?? '').toString().trim();
        final avatarUrl = row['avatar_url']?.toString().trim();
        final bio = row['bio']?.toString().trim();
        if (id.isNotEmpty && uname.isNotEmpty) {
          userIdByLowerName[uname.toLowerCase()] = id;
          if (id != currentUserId) {
            profilesById[id] = {
              'username': uname,
              'full_name': fullName,
              'avatar_url': (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : null,
              'bio': (bio != null && bio.isNotEmpty) ? bio : null,
            };
          }
        }
      }
    } catch (e) {
      debugPrint('[DirectChatRepository] Error al consultar profiles: $e');
    }

    // Consultar mensajes para obtener el último mensaje 1:1 con cada usuario
    final Map<String, Map<String, dynamic>> lastMsgByOtherId = {};
    try {
      final messagesData = await SupabaseConfig.client
          .from(SupabaseConfig.tableMessages)
          .select()
          .order('id', ascending: true);

      for (final raw in (messagesData as List)) {
        final normalized = normalizeMessage(Map<String, dynamic>.from(raw as Map));
        if (normalized == null) continue;

        String sId = (normalized['sender_id'] ?? '').toString();
        String rId = (normalized['receiver_id'] ?? '').toString();
        final sName = (normalized['sender_name'] ?? '').toString();
        final rName = (normalized['receiver_name'] ?? '').toString();

        if (sId.isEmpty && sName.isNotEmpty) {
          sId = userIdByLowerName[sName.toLowerCase()] ?? '';
        }
        if (rId.isEmpty && rName.isNotEmpty) {
          rId = userIdByLowerName[rName.toLowerCase()] ?? '';
        }

        if (sId.isNotEmpty && sId != currentUserId && !profilesById.containsKey(sId)) {
          profilesById[sId] = {
            'username': sName.isNotEmpty ? sName : 'Usuario',
            'full_name': '',
            'avatar_url': null,
            'bio': null,
          };
        }
        if (rId.isNotEmpty && rId != currentUserId && !profilesById.containsKey(rId)) {
          profilesById[rId] = {
            'username': rName.isNotEmpty ? rName : 'Usuario',
            'full_name': '',
            'avatar_url': null,
            'bio': null,
          };
        }

        if (sId == currentUserId && rId.isNotEmpty && rId != currentUserId) {
          lastMsgByOtherId[rId] = normalized;
        } else if (rId == currentUserId && sId.isNotEmpty && sId != currentUserId) {
          lastMsgByOtherId[sId] = normalized;
        }
      }
    } catch (e) {
      debugPrint('[DirectChatRepository] Error al consultar mensajes para resumen: $e');
    }

    final List<DirectChatContact> contacts = [];
    for (final entry in profilesById.entries) {
      final otherId = entry.key;
      final profileInfo = entry.value;
      final displayName = profileInfo['username'] ?? 'Usuario';
      final lastMsg = lastMsgByOtherId[otherId];

      final lastSenderId = (lastMsg?['sender_id'] ?? '').toString();
      final isFromMe = lastMsg != null &&
          (lastSenderId == currentUserId ||
              (lastSenderId.isEmpty &&
                  (lastMsg['sender_name'] ?? '').toString().trim().toLowerCase() ==
                      currentUserName.trim().toLowerCase()));

      final previewText = lastMsg != null ? formatMessagePreview(lastMsg) : null;

      contacts.add(
        DirectChatContact(
          userId: otherId,
          username: displayName,
          fullName: profileInfo['full_name'] ?? '',
          avatarUrl: profileInfo['avatar_url'],
          bio: profileInfo['bio'],
          lastMessage: previewText,
          lastMediaType: lastMsg?['media_type']?.toString(),
          lastTimestamp: lastMsg?['created_at']?.toString(),
          lastMessageId: lastMsg?['id'] as int?,
          isLastFromMe: isFromMe,
        ),
      );
    }

    // Ordenar conversaciones con mensajes más recientes primero, luego alfabéticamente
    contacts.sort((a, b) {
      if (a.lastMessageId != null && b.lastMessageId != null) {
        return b.lastMessageId!.compareTo(a.lastMessageId!);
      }
      if (a.lastMessageId != null) return -1;
      if (b.lastMessageId != null) return 1;
      return a.username.toLowerCase().compareTo(b.username.toLowerCase());
    });

    return contacts;
  }

  /// Obtiene el historial de mensajes 1:1 entre `currentUserId` y `otherUserId`.
  Future<List<Map<String, dynamic>>> fetchDirectMessages({
    required String currentUserId,
    required String otherUserId,
    String? currentUserName,
    String? otherUserName,
  }) async {
    final data = await SupabaseConfig.client
        .from(SupabaseConfig.tableProfiles == 'profiles'
            ? SupabaseConfig.tableMessages
            : SupabaseConfig.tableMessages)
        .select()
        .order('id', ascending: true);

    final List<Map<String, dynamic>> result = [];
    for (final raw in (data as List)) {
      final normalized = normalizeMessage(Map<String, dynamic>.from(raw as Map));
      if (normalized != null &&
          isMessageBetween(
            normalizedMsg: normalized,
            currentUserId: currentUserId,
            otherUserId: otherUserId,
            currentUserName: currentUserName,
            otherUserName: otherUserName,
          )) {
        result.add(normalized);
      }
    }
    return result;
  }

  /// Envía un mensaje 1:1 (texto o multimedia) vinculando `sender_id` y `receiver_id` de forma inmutable.
  Future<Map<String, dynamic>> sendDirectMessage({
    required String senderId,
    required String receiverId,
    required String senderName,
    required String content,
    String? mediaUrl,
    String mediaType = 'text',
    int? fileSizeBytes,
    int? durationSeconds,
  }) async {
    final Map<String, dynamic> payload = {
      'sender_id': senderId,
      'receiver_id': receiverId,
      'sender_name': senderName.trim(),
      'content': content.trim(),
      'media_type': mediaType,
      if (mediaUrl != null && mediaUrl.isNotEmpty) 'media_url': mediaUrl,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
    };

    final inserted = await SupabaseConfig.client
        .from(SupabaseConfig.tableMessages)
        .insert(payload)
        .select()
        .single();

    return normalizeMessage(Map<String, dynamic>.from(inserted))!;
  }
}
