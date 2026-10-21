import 'package:flutter_test/flutter_test.dart';
import 'package:finchat/features/users/models/user_profile.dart';
import 'package:finchat/features/users/services/user_service.dart';

void main() {
  group('UserProfile Model Tests', () {
    test('UserProfile inicializa correctamente y preserva inmutabilidad', () {
      final now = DateTime.now();
      final profile = UserProfile(
        id: 'usr_uuid_10',
        username: 'alice_crypto',
        email: 'alice@finchat.app',
        fullName: 'Alice Walker',
        bio: 'Seguridad y privacidad primero',
        avatarUrl: 'https://supabase.co/storage/v1/alice.png',
        createdAt: now,
      );

      expect(profile.id, equals('usr_uuid_10'));
      expect(profile.username, equals('alice_crypto'));
      expect(profile.email, equals('alice@finchat.app'));
      expect(profile.fullName, equals('Alice Walker'));
      expect(profile.bio, equals('Seguridad y privacidad primero'));
      expect(profile.avatarUrl, equals('https://supabase.co/storage/v1/alice.png'));
      expect(profile.createdAt, equals(now));
    });

    test('UserProfile serialización toMap y fromMap es bidireccional y exacta', () {
      final original = UserProfile(
        id: 'usr_uuid_20',
        username: 'bob_builder',
        email: 'bob@finchat.app',
        fullName: 'Bob Martinez',
        bio: 'Construyendo FinChat',
        avatarUrl: null,
        createdAt: DateTime.parse('2026-05-10T14:30:00.000Z'),
        isOnline: true,
      );

      final map = original.toMap();
      final reconstructed = UserProfile.fromMap(map);

      expect(reconstructed.id, equals(original.id));
      expect(reconstructed.username, equals(original.username));
      expect(reconstructed.email, equals(original.email));
      expect(reconstructed.fullName, equals(original.fullName));
      expect(reconstructed.bio, equals(original.bio));
      expect(reconstructed.avatarUrl, isNull);
      expect(reconstructed.isOnline, isTrue);
      expect(reconstructed.createdAt.toIso8601String(), equals(original.createdAt.toIso8601String()));
    });

    test('UserProfile copyWith actualiza campos manteniendo inalterados los demás', () {
      final base = UserProfile(
        id: 'usr_01',
        username: 'carol',
        email: 'carol@finchat.app',
        fullName: 'Carol Danvers',
        createdAt: DateTime.now(),
      );

      final updated = base.copyWith(
        bio: 'Nueva biografía de Carol',
        avatarUrl: 'https://img.co/carol.jpg',
      );

      expect(updated.id, equals('usr_01'));
      expect(updated.username, equals('carol'));
      expect(updated.email, equals('carol@finchat.app'));
      expect(updated.bio, equals('Nueva biografía de Carol'));
      expect(updated.avatarUrl, equals('https://img.co/carol.jpg'));
    });
  });

  group('UserService MoSCoW Exact Search & Profile Management Tests', () {
    late UserService userService;

    setUp(() {
      userService = UserService();
    });

    test('searchByExactUsername encuentra usuario por coincidencia EXACTA', () async {
      final user = await userService.searchByExactUsername('usuario1');
      expect(user, isNotNull);
      expect(user!.username, equals('usuario1'));
      expect(user.fullName, equals('Carlos Santana'));
    });

    test('searchByExactUsername es case-insensitive y tolera espacios en los extremos', () async {
      final userUpper = await userService.searchByExactUsername('  USUARIO1  ');
      expect(userUpper, isNotNull);
      expect(userUpper!.username, equals('usuario1'));
    });

    test('searchByExactUsername NO realiza búsqueda difusa (debe retornar null ante coincidencia parcial)', () async {
      // Coincidencia parcial no debe encontrar el usuario "usuario1"
      final partialUser = await userService.searchByExactUsername('usuario');
      expect(partialUser, isNull, reason: 'No deben permitirse coincidencias parciales con comodines');

      // Nombre inexistente
      final unknownUser = await userService.searchByExactUsername('no_existe_99');
      expect(unknownUser, isNull);

      // Query vacío o en blanco
      final emptyUser = await userService.searchByExactUsername('   ');
      expect(emptyUser, isNull);
    });

    test('getProfileById recupera usuario por ID o null si no existe', () async {
      final found = await userService.getProfileById('usr_002');
      expect(found, isNotNull);
      expect(found!.username, equals('maria_dev'));

      final notFound = await userService.getProfileById('id_falso');
      expect(notFound, isNull);
    });

    test('updateProfile actualiza biografía y datos del perfil', () async {
      final updated = await userService.updateProfile(
        userId: 'usr_001',
        fullName: 'Carlos Santana Editado',
        bio: 'Nueva bio actualizada',
      );

      expect(updated.fullName, equals('Carlos Santana Editado'));
      expect(updated.bio, equals('Nueva bio actualizada'));

      // Verificar que getProfileById refleje los cambios
      final verified = await userService.getProfileById('usr_001');
      expect(verified?.fullName, equals('Carlos Santana Editado'));
      expect(verified?.bio, equals('Nueva bio actualizada'));
    });

    test('updateProfile rechaza biografías que superen los 160 caracteres (restricción chk_bio_length)', () async {
      final bioExcesiva = 'A' * 161; // 161 caracteres

      expect(
        () => userService.updateProfile(
          userId: 'usr_001',
          bio: bioExcesiva,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
