import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Gestor centralizado de configuración y clientes de Supabase para FinChat.
abstract final class SupabaseConfig {
  SupabaseConfig._();

  // URL del proyecto Supabase
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://tu-proyecto.supabase.co',
  );

  // Clave pública anónima de Supabase con RLS
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'tu-anon-key-publica',
  );

  // Tablas en PostgreSQL
  static const String tableProfiles = 'profiles';
  static const String tableChats = 'chats';
  static const String tableMessages = 'messages';
  static const String tableChatParticipants = 'chat_participants';

  // Buckets en Supabase Storage
  static const String bucketAvatars = 'avatars';
  static const String bucketChatImages = 'chat_images';
  static const String bucketChatAudios = 'chat_audios';
  static const String bucketChatVideos = 'chat_videos';
  static const String bucketChatMedia = 'chat_media';

  static bool _isInitialized = false;

  // Verifica si el SDK de Supabase ya fue inicializado
  static bool get isInitialized {
    if (_isInitialized) return true;
    try {
      Supabase.instance;
      _isInitialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  // Inicializa el SDK de Supabase de manera segura
  static Future<void> initialize({
    String? url,
    String? anonKey,
    String? publishableKey,
  }) async {
    if (isInitialized) return;

    try {
      final effectiveKey = publishableKey ?? anonKey ?? supabaseAnonKey;
      await Supabase.initialize(
        url: url ?? supabaseUrl,
        publishableKey: effectiveKey,
      );
      _isInitialized = true;
    } catch (error, stackTrace) {
      _isInitialized = false;
      debugPrint('[SupabaseConfig] Error al inicializar Supabase: $error\n$stackTrace');
    }
  }

  // Cliente raíz de Supabase
  static SupabaseClient get client {
    if (!isInitialized) {
      throw StateError(
        'Supabase no ha sido inicializado. Ejecuta SupabaseConfig.initialize() antes de usar el cliente.',
      );
    }
    return Supabase.instance.client;
  }

  // Cliente de autenticación
  static GoTrueClient get auth => client.auth;

  // Constructor de consultas PostgREST para una tabla
  static SupabaseQueryBuilder from(String table) => client.from(table);

  // Cliente de almacenamiento de archivos
  static SupabaseStorageClient get storage => client.storage;
}
