import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/supabase/supabase_config.dart';

/// Modelo de contacto y resumen de conversación 1:1 basado en identidad inmutable (UUID).
class DirectChatContact {
  final String userId;
  final String username;
  final String? lastMessage;
  final String? lastTimestamp;
  final int? lastMessageId;
  final bool isLastFromMe;

  const DirectChatContact({
    required this.userId,
    required this.username,
    this.lastMessage,
    this.lastTimestamp,
    this.lastMessageId,
    this.isLastFromMe = false,
  });
}

/// Repositorio para gestionar usuarios con ID único inmutable (`profiles.id`)
/// y mensajes 1:1 vinculados por `sender_id` y `receiver_id`.
class DirectChatRepository {
  DirectChatRepository._();
  static final DirectChatRepository instance = DirectChatRepository._();

  static const String _prefUserIdKey = 'chat_user_id';
  static const String _prefUserNameKey = 'chat_username';
  static const String _presenceMarker = '__SYS_PRESENCE__';
  static final RegExp _legacyRecipientRegex = RegExp(r'^@\[([^\]]+)\]:\s*(.*)$', dotAll: true);
  static const Uuid _uuid = Uuid();

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

  /// Guarda el nombre de usuario localmente y actualiza su perfil en Supabase manteniendo el mismo UUID.
  Future<void> registerOrUpdateUser({
    required String userId,
    required String username,
  }) async {
    final cleanName = username.trim();
    if (cleanName.isEmpty || userId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUserNameKey, cleanName);

    try {
      await SupabaseConfig.client.from(SupabaseConfig.tableProfiles).upsert(
        {
          'id': userId,
          'username': cleanName,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'id',
      );
    } catch (e) {
      debugPrint('[DirectChatRepository] Error al sincronizar perfil en profiles: $e');
    }
  }

  /// Normaliza un registro de `messages`. Extrae `sender_id`, `receiver_id`, `sender_name` y `content`.
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

    return {
      'id': raw['id'],
      'created_at': raw['created_at'],
      'sender_id': senderId,
      'receiver_id': receiverId,
      'sender_name': senderName,
      'receiver_name': legacyReceiverName ?? '',
      'content': cleanContent,
    };
  }

  /// Verifica si un mensaje pertenece a la conversación 1:1 entre el usuario actual y el destinatario.
  /// Prioriza la comparación por UUID (`sender_id` / `receiver_id`), manteniendo soporte de lectura
  /// para mensajes antiguos previos a la migración si coinciden los nombres.
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

    // Fallback sólo para mensajes históricos enviados sin UUID
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
  /// junto con el último mensaje intercambiado por `userId`.
  Future<List<DirectChatContact>> fetchContactsWithLastMessage({
    required String currentUserId,
    required String currentUserName,
  }) async {
    // Mapa de userId -> username actual desde la tabla `profiles`
    final Map<String, String> profilesById = {};
    // Mapa auxiliar de username(lower) -> userId para vincular mensajes históricos sin UUID
    final Map<String, String> userIdByLowerName = {};

    try {
      final profilesData = await SupabaseConfig.client
          .from(SupabaseConfig.tableProfiles)
          .select('id, username')
          .order('username', ascending: true);

      for (final row in (profilesData as List)) {
        final id = (row['id'] ?? '').toString().trim();
        final uname = (row['username'] ?? '').toString().trim();
        if (id.isNotEmpty && uname.isNotEmpty) {
          userIdByLowerName[uname.toLowerCase()] = id;
          if (id != currentUserId) {
            profilesById[id] = uname;
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

        // Si es un mensaje antiguo sin UUID, intentar resolver el UUID por el nombre actual
        if (sId.isEmpty && sName.isNotEmpty) {
          sId = userIdByLowerName[sName.toLowerCase()] ?? '';
        }
        if (rId.isEmpty && rName.isNotEmpty) {
          rId = userIdByLowerName[rName.toLowerCase()] ?? '';
        }

        // Si el mensaje involucra un UUID válido que aún no estaba en profilesById, registrarlo con su último nombre conocido
        if (sId.isNotEmpty && sId != currentUserId && !profilesById.containsKey(sId)) {
          profilesById[sId] = sName.isNotEmpty ? sName : 'Usuario';
        }
        if (rId.isNotEmpty && rId != currentUserId && !profilesById.containsKey(rId)) {
          profilesById[rId] = rName.isNotEmpty ? rName : 'Usuario';
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
      final displayName = entry.value;
      final lastMsg = lastMsgByOtherId[otherId];

      final lastSenderId = (lastMsg?['sender_id'] ?? '').toString();
      final isFromMe = lastMsg != null &&
          (lastSenderId == currentUserId ||
              (lastSenderId.isEmpty &&
                  (lastMsg['sender_name'] ?? '').toString().trim().toLowerCase() ==
                      currentUserName.trim().toLowerCase()));

      contacts.add(
        DirectChatContact(
          userId: otherId,
          username: displayName,
          lastMessage: lastMsg?['content']?.toString(),
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
        .from(SupabaseConfig.tableMessages)
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

  /// Envía un mensaje 1:1 vinculando `sender_id` y `receiver_id` de forma inmutable.
  Future<Map<String, dynamic>> sendDirectMessage({
    required String senderId,
    required String receiverId,
    required String senderName,
    required String content,
  }) async {
    final inserted = await SupabaseConfig.client
        .from(SupabaseConfig.tableMessages)
        .insert({
          'sender_id': senderId,
          'receiver_id': receiverId,
          'sender_name': senderName.trim(),
          'content': content.trim(),
        })
        .select()
        .single();

    return normalizeMessage(Map<String, dynamic>.from(inserted))!;
  }
}
