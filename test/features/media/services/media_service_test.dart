import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:finchat/features/media/models/media_attachment.dart';
import 'package:finchat/features/media/services/media_service.dart';

class FakeImagePicker extends ImagePicker {
  XFile? fileToReturn;
  bool shouldThrow = false;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    if (shouldThrow) {
      throw Exception('Simulated hardware permission failure');
    }
    return fileToReturn;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeImagePicker fakePicker;
  late MediaService mediaService;

  setUp(() {
    fakePicker = FakeImagePicker();
    mediaService = MediaService.custom(picker: fakePicker);
  });

  group('MediaService - Camera & Gallery Capture Tests', () {
    test('capturePhoto returns XFile when user takes a photo', () async {
      fakePicker.fileToReturn = XFile('/tmp/camera_sample.jpg');

      final result = await mediaService.capturePhoto();

      expect(result, isNotNull);
      expect(result!.path, '/tmp/camera_sample.jpg');
    });

    test('capturePhoto handles user cancellation cleanly returning null', () async {
      fakePicker.fileToReturn = null; // Usuario cerró la cámara

      final result = await mediaService.capturePhoto();

      expect(result, isNull);
    });

    test('capturePhoto catches hardware exceptions gracefully without crashing', () async {
      fakePicker.shouldThrow = true;

      final result = await mediaService.capturePhoto();

      expect(result, isNull);
    });

    test('pickImageFromGallery returns XFile when user selects photo', () async {
      fakePicker.fileToReturn = XFile('/tmp/gallery_sample.png');

      final result = await mediaService.pickImageFromGallery();

      expect(result, isNotNull);
      expect(result!.path, '/tmp/gallery_sample.png');
    });

    test('pickImageFromGallery handles user cancellation cleanly returning null', () async {
      fakePicker.fileToReturn = null; // Usuario canceló la galería

      final result = await mediaService.pickImageFromGallery();

      expect(result, isNull);
    });
  });

  group('MediaService - Background Isolate Compression Tests', () {
    test('compressImage compresses large image to < 300 KB with > 85% savings', () async {
      // Simula fotografía de cámara pesada (~4.8 MB)
      const rawSize = 4800000;
      final rawBytes = Uint8List.fromList(List.filled(rawSize, 85));

      final attachment = await mediaService.compressImage(
        rawBytes,
        maxWidth: 1280,
        maxHeight: 720,
        quality: 78,
      );

      // Verificaciones estrictas de requerimiento:
      // 1. Archivo resultante < 300 KB (307,200 bytes)
      expect(attachment.compressedSizeBytes, lessThan(300 * 1024));

      // 2. Ahorro de datos superior al 85%
      expect(attachment.savingsPercent, greaterThan(85.0));

      // 3. Relación de compresión positiva
      expect(attachment.compressionRatio, greaterThan(5.0));

      // 4. Verificación de archivo generado en disco local
      final localFile = File(attachment.localPath);
      expect(await localFile.exists(), isTrue);
      expect(await localFile.length(), attachment.compressedSizeBytes);

      // Limpieza preventiva
      await localFile.delete();
    });

    test('compressImage accepts String path and compresses correctly', () async {
      final tempFile = File('${Directory.systemTemp.path}/test_raw.jpg');
      await tempFile.writeAsBytes(Uint8List.fromList(List.filled(3500000, 120)));

      final attachment = await mediaService.compressImage(tempFile.path);

      expect(attachment.originalSizeBytes, 3500000);
      expect(attachment.compressedSizeBytes, lessThan(300 * 1024));
      expect(attachment.savingsPercent, greaterThan(85.0));

      await tempFile.delete();
      final localFile = File(attachment.localPath);
      if (await localFile.exists()) await localFile.delete();
    });

    test('captureAndCompressPhoto returns null when user cancels', () async {
      fakePicker.fileToReturn = null;

      final attachment = await mediaService.captureAndCompressPhoto();

      expect(attachment, isNull);
    });
  });

  group('MediaService - Supabase Storage Upload & RLS Path Tests', () {
    test('uploadMedia constructs compliant storage path: chat_id/sender_id/filename', () async {
      final tempFile = File('${Directory.systemTemp.path}/upload_test.webp');
      await tempFile.writeAsBytes(Uint8List.fromList([1, 2, 3, 4, 5]));

      const chatId = 'chat_room_889';
      const senderId = 'usr_uuid_456';

      final url = await mediaService.uploadMedia(
        localPath: tempFile.path,
        chatId: chatId,
        senderId: senderId,
        fileName: 'foto_comprimida.webp',
      );

      // Debe apuntar al bucket chat_media y seguir la estructura chat_id/sender_id/filename
      expect(url, contains('chat_media'));
      expect(url, contains('$chatId/$senderId/foto_comprimida.webp'));

      await tempFile.delete();
    });

    test('uploadMediaAttachment updates remoteUrl on MediaAttachment entity', () async {
      final attachment = MediaAttachment(
        id: 'att_upload',
        fileType: MediaFileType.image,
        localPath: '/tmp/test.webp',
        originalSizeBytes: 4000000,
        compressedSizeBytes: 190000,
      );

      final uploaded = await mediaService.uploadMediaAttachment(
        attachment: attachment,
        chatId: 'c_101',
        senderId: 'u_202',
      );

      expect(uploaded.remoteUrl, isNotNull);
      expect(uploaded.remoteUrl, contains('c_101/u_202'));
    });
  });

  group('MediaService - Voice Recording 60s & Video Methods', () {
    test('audio recording state management toggles isRecording flag', () {
      expect(mediaService.isRecording, isFalse);

      mediaService.startVoiceRecording();
      expect(mediaService.isRecording, isTrue);

      mediaService.cancelVoiceRecording();
      expect(mediaService.isRecording, isFalse);
    });

    test('stopVoiceRecording returns audio attachment within 60s limit', () async {
      mediaService.startVoiceRecording();
      final audioAttachment = await mediaService.stopVoiceRecording();

      expect(audioAttachment.fileType, MediaFileType.audio);
      expect(audioAttachment.durationSeconds, inInclusiveRange(1, 60));
      expect(audioAttachment.isAudioMaxExceeded, isFalse);
    });

    test('processCameraPhoto and processVideo return valid attachments', () async {
      final photo = await mediaService.processCameraPhoto();
      expect(photo.fileType, MediaFileType.image);
      expect(photo.compressedSizeBytes, lessThan(photo.originalSizeBytes));

      final video = await mediaService.processVideo();
      expect(video.fileType, MediaFileType.video);
      expect(video.durationSeconds, 18);
    });
  });
}
