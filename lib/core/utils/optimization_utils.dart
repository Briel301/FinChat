import 'dart:math';

/// Utilidades de optimización y formateo para minimizar consumo en Supabase y evitar jank en UI.
class OptimizationUtils {
  /// Formatea bytes a un texto legible (KB, MB).
  static String formatBytes(int bytes, [int decimals = 1]) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  /// Calcula el porcentaje de ahorro obtenido tras una compresión.
  static double calculateSavingsPercent(int originalBytes, int compressedBytes) {
    if (originalBytes <= 0 || compressedBytes >= originalBytes) return 0.0;
    return ((originalBytes - compressedBytes) / originalBytes) * 100.0;
  }

  /// Formatea segundos a formato de temporizador mm:ss (ej. 00:45).
  static String formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Simula el resultado de optimización para imágenes WebP en background.
  /// (En producción se delega a FlutterImageCompress mediante compute()).
  static Map<String, dynamic> estimateImageCompression(int originalSizeBytes) {
    // Estimación empírica: WebP 75% reduce en promedio entre 70% y 85% el peso de JPEG de cámara.
    final compressedBytes = (originalSizeBytes * 0.22).round();
    final savings = calculateSavingsPercent(originalSizeBytes, compressedBytes);
    return {
      'originalBytes': originalSizeBytes,
      'compressedBytes': compressedBytes,
      'savingsPercent': savings,
    };
  }

  /// Simula el resultado de optimización para audio AAC mono (32 kbps).
  /// Un minuto de audio en 32 kbps mono pesa ~240 KB en lugar de ~10 MB sin comprimir.
  static Map<String, dynamic> estimateAudioCompression(int durationSeconds) {
    final originalRawWav = durationSeconds * 44100 * 2 * 2; // 44.1kHz, 16bit, stereo
    final compressedAac = (durationSeconds * 4000); // ~32 kbps mono
    return {
      'durationSeconds': durationSeconds,
      'originalBytes': originalRawWav,
      'compressedBytes': compressedAac,
      'savingsPercent': calculateSavingsPercent(originalRawWav, compressedAac),
    };
  }
}
