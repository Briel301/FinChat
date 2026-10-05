/// Configuración de constantes y nombres de tablas/buckets para Supabase.
class SupabaseConfig {
  /// URL del proyecto en Supabase (debe configurarse con variables de entorno en producción).
  static const String supabaseUrl = 'https://tu-proyecto.supabase.co';

  /// Anon Key pública de Supabase con Row Level Security (RLS) habilitado.
  static const String supabaseAnonKey = 'tu-anon-key-publica';

  // --- Nombres de Tablas de Base de Datos (PostgreSQL) ---
  static const String tableProfiles = 'profiles';
  static const String tableChats = 'chats';
  static const String tableMessages = 'messages';
  static const String tableChatParticipants = 'chat_participants';

  // --- Nombres de Buckets de Almacenamiento (Supabase Storage) ---
  /// Bucket para avatares de perfil (WebP, máx 256x256, máx 100 KB)
  static const String bucketAvatars = 'avatars';

  /// Bucket para fotos y capturas enviadas en chats (comprimidas a WebP/JPEG, calidad 75%)
  static const String bucketChatImages = 'chat_images';

  /// Bucket para notas de audio (formato AAC mono, máx 1 minuto, máx 300 KB)
  static const String bucketChatAudios = 'chat_audios';

  /// Bucket para videos comprimidos (H.264 720p/480p)
  static const String bucketChatVideos = 'chat_videos';
}
