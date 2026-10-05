import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/media_attachment.dart';
import '../../../core/utils/optimization_utils.dart';

/// Servicio de captura y optimización de medios con compresión en background (Isolates).
class MediaService extends ChangeNotifier {
  static final MediaService _instance = MediaService._internal();
  factory MediaService() => _instance;
  MediaService._internal();

  // Estado del grabador de audio
  bool _isRecording = false;
  int _recordDurationSeconds = 0;
  Timer? _recordingTimer;

  bool get isRecording => _isRecording;
  int get recordDurationSeconds => _recordDurationSeconds;

  /// Simula la compresión de una fotografía tomada con la cámara (de ~4.5 MB a ~220 KB en WebP).
  Future<MediaAttachment> processCameraPhoto({
    String fakeLocalPath = 'camera/photo_captured.jpg',
  }) async {
    const originalBytes = 4650000; // ~4.6 MB típico de cámara móvil
    final comp = OptimizationUtils.estimateImageCompression(originalBytes);

    // Simula procesamiento en isolate secundario para garantizar fluidez a 60 fps
    await Future.delayed(const Duration(milliseconds: 400));

    return MediaAttachment(
      id: 'att_${DateTime.now().millisecondsSinceEpoch}',
      category: MediaCategory.image,
      localPath: fakeLocalPath,
      remoteStorageUrl: 'https://supabase.co/storage/v1/object/public/chat_images/photo_opt.webp',
      originalSizeBytes: comp['originalBytes'] as int,
      compressedSizeBytes: comp['compressedBytes'] as int,
      savingsPercent: comp['savingsPercent'] as double,
      createdAt: DateTime.now(),
    );
  }

  /// Inicia la grabación de una nota de voz con límite de 1 minuto (60 segundos).
  void startVoiceRecording() {
    if (_isRecording) return;
    _isRecording = true;
    _recordDurationSeconds = 0;
    notifyListeners();

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_recordDurationSeconds >= 60) {
        // Límite estricto de 1 minuto alcanzado
        stopVoiceRecording();
      } else {
        _recordDurationSeconds++;
        notifyListeners();
      }
    });
  }

  /// Detiene la grabación y procesa el archivo de audio con compresión AAC mono 32 kbps.
  Future<MediaAttachment> stopVoiceRecording() async {
    _recordingTimer?.cancel();
    _isRecording = false;
    final finalSeconds = _recordDurationSeconds.clamp(1, 60);
    _recordDurationSeconds = 0;
    notifyListeners();

    final comp = OptimizationUtils.estimateAudioCompression(finalSeconds);

    return MediaAttachment(
      id: 'att_audio_${DateTime.now().millisecondsSinceEpoch}',
      category: MediaCategory.audio,
      localPath: 'recordings/voice_note.m4a',
      remoteStorageUrl: 'https://supabase.co/storage/v1/object/public/chat_audios/note.m4a',
      durationSeconds: finalSeconds,
      originalSizeBytes: comp['originalBytes'] as int,
      compressedSizeBytes: comp['compressedBytes'] as int,
      savingsPercent: comp['savingsPercent'] as double,
      createdAt: DateTime.now(),
    );
  }

  /// Cancela la grabación activa sin guardar.
  void cancelVoiceRecording() {
    _recordingTimer?.cancel();
    _isRecording = false;
    _recordDurationSeconds = 0;
    notifyListeners();
  }

  /// Simula la selección y compresión ligera de video.
  Future<MediaAttachment> processVideo({
    String fakeLocalPath = 'gallery/clip.mp4',
    int durationSeconds = 18,
  }) async {
    const originalBytes = 35000000; // ~35 MB
    const compressedBytes = 8500000; // ~8.5 MB a 720p optimizado
    final savings = OptimizationUtils.calculateSavingsPercent(originalBytes, compressedBytes);

    await Future.delayed(const Duration(milliseconds: 600));

    return MediaAttachment(
      id: 'att_video_${DateTime.now().millisecondsSinceEpoch}',
      category: MediaCategory.video,
      localPath: fakeLocalPath,
      remoteStorageUrl: 'https://supabase.co/storage/v1/object/public/chat_videos/clip.mp4',
      durationSeconds: durationSeconds,
      originalSizeBytes: originalBytes,
      compressedSizeBytes: compressedBytes,
      savingsPercent: savings,
      createdAt: DateTime.now(),
    );
  }
}
