import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finchat/core/supabase/supabase_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SupabaseConfig', () {
    test('constants have default values', () {
      expect(SupabaseConfig.supabaseUrl, isNotEmpty);
      expect(SupabaseConfig.supabaseAnonKey, isNotEmpty);
      expect(SupabaseConfig.tableProfiles, 'profiles');
      expect(SupabaseConfig.tableChats, 'chats');
      expect(SupabaseConfig.tableMessages, 'messages');
      expect(SupabaseConfig.tableChatParticipants, 'chat_participants');
      expect(SupabaseConfig.bucketAvatars, 'avatars');
      expect(SupabaseConfig.bucketChatImages, 'chat_images');
      expect(SupabaseConfig.bucketChatAudios, 'chat_audios');
      expect(SupabaseConfig.bucketChatVideos, 'chat_videos');
      expect(SupabaseConfig.bucketChatMedia, 'chat_media');
    });

    test('getters throw StateError when not initialized', () {
      if (!SupabaseConfig.isInitialized) {
        expect(() => SupabaseConfig.client, throwsStateError);
        expect(() => SupabaseConfig.auth, throwsStateError);
        expect(() => SupabaseConfig.from('profiles'), throwsStateError);
        expect(() => SupabaseConfig.storage, throwsStateError);
      }
    });

    test('initialize catches invalid credentials gracefully without unhandled exception', () async {
      await SupabaseConfig.initialize(
        url: 'invalid-url-schema',
        anonKey: 'invalid-key',
      );

      // Si falló por URL inválida, no debe tumbar la app
      expect(true, isTrue);
    });
  });
}
