enum MediaCategory { image, video, audio }

/// Representa un archivo adjunto multimedia con información de compresión y ahorro.
class MediaAttachment {
  final String id;
  final MediaCategory category;
  final String localPath;
  final String? remoteStorageUrl;
  final int originalSizeBytes;
  final int compressedSizeBytes;
  final int? durationSeconds; // Para notas de voz (máx 60) o video
  final double savingsPercent;
  final DateTime createdAt;

  const MediaAttachment({
    required this.id,
    required this.category,
    required this.localPath,
    this.remoteStorageUrl,
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
    this.durationSeconds,
    required this.savingsPercent,
    required this.createdAt,
  });

  bool get isAudioMaxExceeded => (durationSeconds ?? 0) > 60;
}
