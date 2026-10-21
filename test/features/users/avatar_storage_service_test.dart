import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:finchat/features/users/services/avatar_storage_service.dart';
import 'package:finchat/features/users/services/user_service.dart';
import 'package:finchat/core/utils/optimization_utils.dart';

void main() {
  group('AvatarUploadResult Model Tests', () {
    test('AvatarUploadResult calcula meetsSizeTarget para imágenes menores a 35 KB', () {
      const resultLight = AvatarUploadResult(
        publicUrl: 'https://supabase.co/storage/v1/object/public/avatars/u1.webp',
        storagePath: 'avatars/u1.webp',
        originalSizeBytes: 4 * 1024 * 1024, // 4 MB
        compressedSizeBytes: 28 * 1024,     // 28 KB (< 35 KB)
        savingsPercentage: 99.3,
        isUpsert: true,
      );

      expect(resultLight.meetsSizeTarget, isTrue);
      expect(resultLight.isUpsert, isTrue);
      expect(resultLight.savingsPercentage, greaterThan(90.0));
      expect(resultLight.toString(), contains('ahorro: 99.3%'));

      const resultHeavy = AvatarUploadResult(
        publicUrl: 'https://supabase.co/storage/v1/object/public/avatars/u2.webp',
        storagePath: 'avatars/u2.webp',
        originalSizeBytes: 4 * 1024 * 1024,
        compressedSizeBytes: 50 * 1024, // 50 KB (> 35 KB)
        savingsPercentage: 98.7,
      );

      expect(resultHeavy.meetsSizeTarget, isFalse);
    });
  });

  group('AvatarStorageService Compression & Upsert Tests', () {
    late AvatarStorageService avatarService;
    late UserService userService;

    setUp(() {
      userService = UserService();
      avatarService = AvatarStorageService(userService: userService);
    });

    test('Compresión en Isolate logra reducción de peso comprobada > 90% y < 35 KB', () async {
      // Simulación de foto cruda de cámara de ~3.5 MB (3.5 * 1024 * 1024 bytes)
      final rawPhotoBytes = Uint8List(3670016);
      for (int i = 0; i < 1000; i++) {
        rawPhotoBytes[i] = i % 256;
      }

      // Ejecución de compresión mediante OptimizationUtils en isolate
      final compressedBytes = await avatarService.compressAvatarBytes(rawPhotoBytes);

      // Verificación de reducción de peso
      final savings = OptimizationUtils.calculateSavingsPercentage(
        rawPhotoBytes.length,
        compressedBytes.length,
      );

      expect(compressedBytes.length, lessThanOrEqualTo(35 * 1024),
          reason: 'El peso comprimido debe ser menor a 35 KB');
      expect(savings, greaterThan(90.0),
          reason: 'El ahorro de bytes debe superar el 90% frente al original de cámara');
    });

    test('uploadProcessedAvatar genera ruta normalizada avatars/{userId}.webp y actualiza perfil', () async {
      final rawPhotoBytes = Uint8List(2097152); // 2 MB

      final result = await avatarService.uploadProcessedAvatar(
        userId: 'usr_001',
        rawBytes: rawPhotoBytes,
      );

      // Verificación de ruta normalizada y upsert
      expect(result.storagePath, equals('avatars/usr_001.webp'));
      expect(result.publicUrl, contains('avatars/usr_001.webp'));
      expect(result.isUpsert, isTrue);
      expect(result.meetsSizeTarget, isTrue);

      // Verificación de sincronización automática en el perfil del usuario
      final profile = await userService.getProfileById('usr_001');
      expect(profile, isNotNull);
      expect(profile!.avatarUrl, equals(result.publicUrl));
    });

    test('uploadProcessedAvatar rechaza userId vacío', () async {
      final rawBytes = Uint8List(512);

      expect(
        () => avatarService.uploadProcessedAvatar(
          userId: '   ',
          rawBytes: rawBytes,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ensureAvatarBucketExists ejecuta sin lanzar excepciones no controladas', () async {
      await expectLater(
        avatarService.ensureAvatarBucketExists(),
        completes,
      );
    });
  });
}
