import 'package:flutter/foundation.dart';
import '../../../core/supabase/supabase_config.dart';

/// Modelo de resumen de contacto / conversación 1:1.
class DirectChatContact {
  final String username;
  final String? lastMessage;
  final String? lastTimestamp;
  final int? lastMessageId;
  final bool isLastFromMe;

  const DirectChatContact({
    required this.username,
    this.lastMessage,
    this.lastTimestamp,
    this.lastMessageId,
    this.isLastFromMe = false,
  });
}

/// Repositorio para gestionar usuarios y mensajes 1:1 en tiempo real con Supabase.
/// Soporta de forma nativa la tabla `profiles` y la columna `receiver_name` en `messages`,
/// e incluye fallback automático en caso de que aún no se haya ejecutado la migración SQL.
class DirectChatRepository {
  DirectChatRepository._();
  static final DirectChatRepository instance = DirectChatRepository._();

  static const String _presenceMarker = '__SYS_PRESENCE__';
  static final RegExp _fallbackRecipientRegex = RegExp(r'^@\[([^\]]+)\]:\s*(.*)$', dotAll: true);

  bool? _hasProfilesTable;
  bool? _hasReceiverColumn;

  /// Normaliza un registro crudo de la tabla `messages` para extraer `sender_name`,
  /// `receiver_name` y `content` (compatible con columna nativa o prefijo `@[usuario]:`).
  Map<String, dynamic>? normalizeMessage(Map<String, dynamic> raw) {
    final sender = (raw['sender_name'] ?? '').toString().trim();
    final rawContent = (raw['content'] ?? '').toString();

    if (sender.isEmpty) return null;

    // Si es un marcador de presencia del sistema, no es un mensaje visible de chat
    if (rawContent == _presenceMarker) {
      return null;
    }

    String? receiver = raw['receiver_name']?.toString().trim();
    String cleanContent = rawContent;

    if (receiver == null || receiver.isEmpty) {
      final match = _fallbackRecipientRegex.firstMatch(rawContent);
      if (match != null) {
        receiver = match.group(1)?.trim();
        cleanContent = match.group(2) ?? '';
      }
    }

    return {
      'id': raw['id'],
      'created_at': raw['created_at'],
      'sender_name': sender,
      'receiver_name': receiver ?? '',
      'content': cleanContent,
    };
  }

  /// Verifica si un mensaje normalizado pertenece a la conversación 1:1 entre `userA` y `userB`.
  bool isMessageBetween(Map<String, dynamic> normalizedMsg, String userA, String userB) {
    final a = userA.trim().toLowerCase();
    final b = userB.trim().toLowerCase();
    final sender = (normalizedMsg['sender_name'] ?? '').toString().trim().toLowerCase();
    final receiver = (normalizedMsg['receiver_name'] ?? '').toString().trim().toLowerCase();

    return (sender == a && receiver == b) || (sender == b && receiver == a);
  }

  /// Registra o actualiza la presencia del usuario actual en Supabase.
  Future<void> registerOrUpdateUser(String username) async {
    final cleanName = username.trim();
    if (cleanName.isEmpty) return;

    // 1. Intentar registrar en la tabla `profiles` si está disponible
    if (_hasProfilesTable != false) {
      try {
        await SupabaseConfig.client.from(SupabaseConfig.tableProfiles).upsert(
          {'username': cleanName},
          onConflict: 'username',
        );
        _hasProfilesTable = true;
        return;
      } catch (e) {
        debugPrint('[DirectChatRepository] Tabla profiles no disponible o sin upsert, usando fallback: $e');
        _hasProfilesTable = false;
      }
    }

    // 2. Fallback: asegurar que el usuario aparezca en el directorio mediante un registro de presencia
    try {
      final existing = await SupabaseConfig.client
          .from(SupabaseConfig.tableMessages)
          .select('id')
          .ilike('sender_name', cleanName)
          .limit(1);

      if ((existing as List).isEmpty) {
        await SupabaseConfig.client.from(SupabaseConfig.tableMessages).insert({
          'sender_name': cleanName,
          'content': _presenceMarker,
        });
      }
    } catch (e) {
      debugPrint('[DirectChatRepository] Error al registrar presencia de usuario: $e');
    }
  }

  /// Obtiene todos los contactos disponibles y su último mensaje 1:1 con `currentUserName`.
  Future<List<DirectChatContact>> fetchContactsWithLastMessage(String currentUserName) async {
    final meLower = currentUserName.trim().toLowerCase();
    final Map<String, String> displayNamesByLower = {};

    // 1. Consultar usuarios en `profiles` si existe la tabla
    if (_hasProfilesTable != false) {
      try {
        final profilesData = await SupabaseConfig.client
            .from(SupabaseConfig.tableProfiles)
            .select('username')
            .order('username', ascending: true);
        _hasProfilesTable = true;

        for (final row in (profilesData as List)) {
          final uname = (row['username'] ?? '').toString().trim();
          if (uname.isNotEmpty && uname.toLowerCase() != meLower) {
            displayNamesByLower[uname.toLowerCase()] = uname;
          }
        }
      } catch (_) {
        _hasProfilesTable = false;
      }
    }

    // 2. Consultar mensajes para descubrir usuarios activos y armar el resumen 1:1
    final messagesData = await SupabaseConfig.client
        .from(SupabaseConfig.tableMessages)
        .select()
        .order('id', ascending: true);

    final Map<String, Map<String, dynamic>> lastMsgByOtherUser = {};

    for (final raw in (messagesData as List)) {
      final map = Map<String, dynamic>.from(raw as Map);
      final rawSender = (map['sender_name'] ?? '').toString().trim();

      // Ignorar usuario de prueba automática inicial si no es relevante
      if (rawSender.isNotEmpty &&
          rawSender.toLowerCase() != meLower &&
          rawSender.toLowerCase() != 'sistema test') {
        displayNamesByLower.putIfAbsent(rawSender.toLowerCase(), () => rawSender);
      }

      final normalized = normalizeMessage(map);
      if (normalized == null) continue;

      final sender = (normalized['sender_name'] ?? '').toString().trim();
      final receiver = (normalized['receiver_name'] ?? '').toString().trim();

      if (receiver.isNotEmpty &&
          receiver.toLowerCase() != meLower &&
          receiver.toLowerCase() != 'sistema test') {
        displayNamesByLower.putIfAbsent(receiver.toLowerCase(), () => receiver);
      }

      // Verificar si es un mensaje 1:1 conmigo
      final senderLower = sender.toLowerCase();
      final receiverLower = receiver.toLowerCase();

      if (senderLower == meLower && receiverLower.isNotEmpty && receiverLower != meLower) {
        lastMsgByOtherUser[receiverLower] = normalized;
      } else if (receiverLower == meLower && senderLower.isNotEmpty && senderLower != meLower) {
        lastMsgByOtherUser[senderLower] = normalized;
      }
    }

    final List<DirectChatContact> contacts = [];
    for (final entry in displayNamesByLower.entries) {
      final otherLower = entry.key;
      final displayName = entry.value;
      final lastMsg = lastMsgByOtherUser[otherLower];

      contacts.add(
        DirectChatContact(
          username: displayName,
          lastMessage: lastMsg?['content']?.toString(),
          lastTimestamp: lastMsg?['created_at']?.toString(),
          lastMessageId: lastMsg?['id'] as int?,
          isLastFromMe: lastMsg != null &&
              (lastMsg['sender_name'] ?? '').toString().trim().toLowerCase() == meLower,
        ),
      );
    }

    // Ordenar: conversaciones con mensajes más recientes primero, luego alfabéticamente
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

  /// Obtiene el historial de mensajes 1:1 entre `currentUser` y `otherUser`.
  Future<List<Map<String, dynamic>>> fetchDirectMessages({
    required String currentUser,
    required String otherUser,
  }) async {
    final data = await SupabaseConfig.client
        .from(SupabaseConfig.tableMessages)
        .select()
        .order('id', ascending: true);

    final List<Map<String, dynamic>> result = [];
    for (final raw in (data as List)) {
      final normalized = normalizeMessage(Map<String, dynamic>.from(raw as Map));
      if (normalized != null && isMessageBetween(normalized, currentUser, otherUser)) {
        result.add(normalized);
      }
    }
    return result;
  }

  /// Envía un mensaje 1:1 desde `sender` hacia `receiver`.
  Future<Map<String, dynamic>> sendDirectMessage({
    required String sender,
    required String receiver,
    required String content,
  }) async {
    final cleanSender = sender.trim();
    final cleanReceiver = receiver.trim();
    final cleanContent = content.trim();

    if (_hasReceiverColumn != false) {
      try {
        final inserted = await SupabaseConfig.client
            .from(SupabaseConfig.tableMessages)
            .insert({
              'sender_name': cleanSender,
              'receiver_name': cleanReceiver,
              'content': cleanContent,
            })
            .select()
            .single();
        _hasReceiverColumn = true;
        return normalizeMessage(Map<String, dynamic>.from(inserted))!;
      } catch (e) {
        debugPrint('[DirectChatRepository] Columna receiver_name no encontrada, usando formato 1:1 compatible: $e');
        _hasReceiverColumn = false;
      }
    }

    // Fallback compatible con esquema sin columna receiver_name
    final encodedContent = '@[$cleanReceiver]: $cleanContent';
    final inserted = await SupabaseConfig.client
        .from(SupabaseConfig.tableMessages)
        .insert({
          'sender_name': cleanSender,
          'content': encodedContent,
        })
        .select()
        .single();

    return normalizeMessage(Map<String, dynamic>.from(inserted))!;
  }
}
