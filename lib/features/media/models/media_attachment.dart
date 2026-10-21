import 'package:flutter/foundation.dart';

/// Tipos de archivos multimedia admitidos en FinChat.
enum MediaFileType {
  image,
  video,
  audio;

  static MediaFileType fromString(String? value) {
    if (value == null) return MediaFileType.image;
    return MediaFileType.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => MediaFileType.image,
    );
  }
}

/// Alias para mantener compatibilidad con referencias históricas a [MediaCategory].
typedef MediaCategory = MediaFileType;

/// Entidad inmutable que representa un archivo multimedia procesado y optimizado.
@immutable
class MediaAttachment {
  /// Identificador único del archivo adjunto.
  final String id;

  /// Tipo de medio: image, video o audio.
  final MediaFileType fileType;

  /// Ruta en el almacenamiento local del dispositivo.
  final String localPath;

  /// URL remota en Supabase Storage (null si aún no ha sido subido).
  final String? remoteUrl;

  /// Tamaño en bytes del archivo original antes de optimizar.
  final int originalSizeBytes;

  /// Tamaño en bytes del archivo resultante tras la compresión.
  final int compressedSizeBytes;

  /// Duración en segundos (para notas de voz [máx 60s] o clips de video).
  final int? durationSeconds;

  /// Porcentaje de ahorro de datos precalculado o provisto.
  final double? _savingsPercent;

  /// Marca de tiempo de captura/procesamiento.
  final DateTime createdAt;

  MediaAttachment({
    required this.id,
    MediaFileType? fileType,
    MediaFileType? category,
    required this.localPath,
    String? remoteUrl,
    String? remoteStorageUrl,
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
    this.durationSeconds,
    double? savingsPercent,
    DateTime? createdAt,
  })  : fileType = fileType ?? category ?? MediaFileType.image,
        remoteUrl = remoteUrl ?? remoteStorageUrl,
        _savingsPercent = savingsPercent,
        createdAt = createdAt ?? DateTime.now();

  /// Accesor de compatibilidad para código que use [category].
  MediaFileType get category => fileType;

  /// Accesor de compatibilidad para código que use [remoteStorageUrl].
  String? get remoteStorageUrl => remoteUrl;

  /// Porcentaje de reducción de tamaño entre 0 y 100%.
  double get savingsPercent {
    if (_savingsPercent != null) return _savingsPercent!;
    if (originalSizeBytes <= 0 || compressedSizeBytes >= originalSizeBytes) return 0.0;
    return ((originalSizeBytes - compressedSizeBytes) / originalSizeBytes) * 100.0;
  }

  /// Alias semántico para el porcentaje de ahorro de datos.
  double get savingsPercentage => savingsPercent;

  /// Relación de compresión (ej. 4.5:1 significa que el original era 4.5 veces más pesado).
  double get compressionRatio {
    if (compressedSizeBytes <= 0) return 1.0;
    if (originalSizeBytes <= 0) return 1.0;
    return originalSizeBytes / compressedSizeBytes;
  }

  /// Cantidad total de bytes ahorrados tras la optimización.
  int get savedBytes =>
      originalSizeBytes > compressedSizeBytes ? originalSizeBytes - compressedSizeBytes : 0;

  /// Valida si una nota de voz superó el límite estricto de 60 segundos.
  bool get isAudioMaxExceeded => (durationSeconds ?? 0) > 60;

  /// Retorna una copia inmutable con valores reemplazados.
  MediaAttachment copyWith({
    String? id,
    MediaFileType? fileType,
    String? localPath,
    String? remoteUrl,
    int? originalSizeBytes,
    int? compressedSizeBytes,
    int? durationSeconds,
    double? savingsPercent,
    DateTime? createdAt,
  }) {
    return MediaAttachment(
      id: id ?? this.id,
      fileType: fileType ?? this.fileType,
      localPath: localPath ?? this.localPath,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      originalSizeBytes: originalSizeBytes ?? this.originalSizeBytes,
      compressedSizeBytes: compressedSizeBytes ?? this.compressedSizeBytes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      savingsPercent: savingsPercent ?? _savingsPercent,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Serialización a Map para persistencia o transporte.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_type': fileType.name,
      'local_path': localPath,
      'remote_url': remoteUrl,
      'original_size_bytes': originalSizeBytes,
      'compressed_size_bytes': compressedSizeBytes,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      'savings_percent': savingsPercent,
      'compression_ratio': compressionRatio,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory MediaAttachment.fromMap(Map<String, dynamic> map) {
    return MediaAttachment(
      id: map['id'] as String? ?? '',
      fileType: MediaFileType.fromString((map['file_type'] ?? map['category']) as String?),
      localPath: map['local_path'] as String? ?? '',
      remoteUrl: (map['remote_url'] ?? map['remote_storage_url']) as String?,
      originalSizeBytes: (map['original_size_bytes'] ?? map['originalSizeBytes']) as int? ?? 0,
      compressedSizeBytes: (map['compressed_size_bytes'] ?? map['compressedSizeBytes']) as int? ?? 0,
      durationSeconds: (map['duration_seconds'] ?? map['durationSeconds']) as int?,
      savingsPercent: (map['savings_percent'] ?? map['savingsPercent']) as double?,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() => toMap();
  factory MediaAttachment.fromJson(Map<String, dynamic> json) => MediaAttachment.fromMap(json);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaAttachment &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          fileType == other.fileType &&
          localPath == other.localPath &&
          remoteUrl == other.remoteUrl &&
          originalSizeBytes == other.originalSizeBytes &&
          compressedSizeBytes == other.compressedSizeBytes &&
          durationSeconds == other.durationSeconds;

  @override
  int get hashCode =>
      id.hashCode ^
      fileType.hashCode ^
      localPath.hashCode ^
      (remoteUrl?.hashCode ?? 0) ^
      originalSizeBytes.hashCode ^
      compressedSizeBytes.hashCode ^
      (durationSeconds?.hashCode ?? 0);

  @override
  String toString() =>
      'MediaAttachment(id: $id, type: ${fileType.name}, local: $localPath, '
      'remote: $remoteUrl, orig: $originalSizeBytes, comp: $compressedSizeBytes, '
      'savings: ${savingsPercent.toStringAsFixed(1)}%)';
}
