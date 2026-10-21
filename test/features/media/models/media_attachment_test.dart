import 'package:flutter_test/flutter_test.dart';
import 'package:finchat/features/media/models/media_attachment.dart';

void main() {
  group('MediaAttachment Entity & Getters Tests', () {
    test('instantiates correctly with immutability and default values', () {
      final now = DateTime(2026, 10, 13, 10, 0, 0);
      final attachment = MediaAttachment(
        id: 'att_001',
        fileType: MediaFileType.image,
        localPath: '/tmp/photo.webp',
        remoteUrl: 'https://supabase.co/storage/v1/object/public/chat_media/c1/u1/photo.webp',
        originalSizeBytes: 4500000, // 4.5 MB
        compressedSizeBytes: 220000, // 220 KB (<300 KB)
        createdAt: now,
      );

      expect(attachment.id, 'att_001');
      expect(attachment.fileType, MediaFileType.image);
      expect(attachment.category, MediaFileType.image); // Alias retrocompatible
      expect(attachment.localPath, '/tmp/photo.webp');
      expect(attachment.remoteUrl, 'https://supabase.co/storage/v1/object/public/chat_media/c1/u1/photo.webp');
      expect(attachment.remoteStorageUrl, attachment.remoteUrl); // Alias retrocompatible
      expect(attachment.originalSizeBytes, 4500000);
      expect(attachment.compressedSizeBytes, 220000);
      expect(attachment.createdAt, now);
    });

    test('calculates compressionRatio, savingsPercent and savedBytes accurately (>85% saving)', () {
      const originalBytes = 5000000; // 5 MB
      const compressedBytes = 250000; // 250 KB (< 300 KB)

      final attachment = MediaAttachment(
        id: 'att_ratio_test',
        fileType: MediaFileType.image,
        localPath: '/tmp/img.webp',
        originalSizeBytes: originalBytes,
        compressedSizeBytes: compressedBytes,
      );

      // Relación de compresión 5,000,000 / 250,000 = 20.0
      expect(attachment.compressionRatio, closeTo(20.0, 0.01));

      // Ahorro: (5000000 - 250000) / 5000000 * 100 = 95.0%
      expect(attachment.savingsPercent, closeTo(95.0, 0.1));
      expect(attachment.savingsPercentage, closeTo(95.0, 0.1));
      expect(attachment.savingsPercent, greaterThan(85.0));

      // Bytes ahorrados: 4,750,000 bytes
      expect(attachment.savedBytes, 4750000);
    });

    test('handles edge cases in savings and ratio (zero bytes or compressed >= original)', () {
      final edgeAttachment = MediaAttachment(
        id: 'att_edge',
        fileType: MediaFileType.image,
        localPath: '/tmp/test.webp',
        originalSizeBytes: 100,
        compressedSizeBytes: 150,
      );

      expect(edgeAttachment.savingsPercent, 0.0);
      expect(edgeAttachment.savedBytes, 0);

      final zeroAttachment = MediaAttachment(
        id: 'att_zero',
        fileType: MediaFileType.image,
        localPath: '/tmp/test.webp',
        originalSizeBytes: 0,
        compressedSizeBytes: 0,
      );

      expect(zeroAttachment.savingsPercent, 0.0);
      expect(zeroAttachment.compressionRatio, 1.0);
      expect(zeroAttachment.savedBytes, 0);
    });

    test('validates isAudioMaxExceeded correctly for voice notes (limit: 60s)', () {
      final validAudio = MediaAttachment(
        id: 'att_audio_ok',
        fileType: MediaFileType.audio,
        localPath: '/tmp/audio.m4a',
        durationSeconds: 60,
        originalSizeBytes: 1000000,
        compressedSizeBytes: 240000,
      );
      expect(validAudio.isAudioMaxExceeded, isFalse);

      final exceededAudio = MediaAttachment(
        id: 'att_audio_exceeded',
        fileType: MediaFileType.audio,
        localPath: '/tmp/audio_long.m4a',
        durationSeconds: 61,
        originalSizeBytes: 1020000,
        compressedSizeBytes: 245000,
      );
      expect(exceededAudio.isAudioMaxExceeded, isTrue);
    });

    test('serializes to Map and deserializes from Map/JSON preserving all fields', () {
      final original = MediaAttachment(
        id: 'att_json',
        fileType: MediaFileType.video,
        localPath: '/tmp/video.mp4',
        remoteUrl: 'https://supabase.co/storage/v1/object/public/chat_media/c1/u1/video.mp4',
        originalSizeBytes: 20000000,
        compressedSizeBytes: 5000000,
        durationSeconds: 15,
      );

      final map = original.toMap();
      final fromMap = MediaAttachment.fromMap(map);

      expect(fromMap.id, original.id);
      expect(fromMap.fileType, original.fileType);
      expect(fromMap.localPath, original.localPath);
      expect(fromMap.remoteUrl, original.remoteUrl);
      expect(fromMap.originalSizeBytes, original.originalSizeBytes);
      expect(fromMap.compressedSizeBytes, original.compressedSizeBytes);
      expect(fromMap.durationSeconds, original.durationSeconds);
      expect(fromMap.savingsPercent, closeTo(75.0, 0.1));
    });

    test('copyWith creates new instance with updated properties', () {
      final original = MediaAttachment(
        id: 'att_copy',
        fileType: MediaFileType.image,
        localPath: '/tmp/orig.jpg',
        originalSizeBytes: 4000000,
        compressedSizeBytes: 200000,
      );

      final updated = original.copyWith(
        remoteUrl: 'https://supabase.co/media.webp',
        compressedSizeBytes: 180000,
      );

      expect(updated.id, original.id);
      expect(updated.remoteUrl, 'https://supabase.co/media.webp');
      expect(updated.compressedSizeBytes, 180000);
      expect(original.remoteUrl, isNull);
    });
  });
}
