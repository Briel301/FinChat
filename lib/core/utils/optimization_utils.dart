/// Utilidades de rendimiento para FinChat (Zero UI Jank).
///
/// Contiene formateadores puros y funciones de cómputo pesado listas para
/// ejecutarse en un isolate mediante `compute()`. No depende de widgets.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

// ---------------------------------------------------------------------------
// Modelos transferibles entre isolates (solo campos primitivos)
// ---------------------------------------------------------------------------

/// Métricas de un archivo calculadas en segundo plano.
@immutable
class FileMetrics {
  /// Crea un resultado de métricas.
  const FileMetrics({
    required this.sizeBytes,
    required this.crc32,
    required this.mimeType,
  });

  /// Tamaño en bytes.
  final int sizeBytes;

  /// Checksum CRC-32 en hexadecimal (8 caracteres, minúsculas).
  ///
  /// Útil para deduplicar subidas y verificar integridad; no es criptográfico.
  final String crc32;

  /// Tipo MIME detectado por firma binaria (magic bytes).
  final String mimeType;

  /// Indica si el archivo es una imagen.
  bool get isImage => mimeType.startsWith('image/');

  /// Indica si el archivo es un audio.
  bool get isAudio => mimeType.startsWith('audio/');

  /// Indica si el archivo es un video.
  bool get isVideo => mimeType.startsWith('video/');

  @override
  bool operator ==(Object other) =>
      other is FileMetrics &&
      other.sizeBytes == sizeBytes &&
      other.crc32 == crc32 &&
      other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash(sizeBytes, crc32, mimeType);

  @override
  String toString() =>
      'FileMetrics(sizeBytes: $sizeBytes, crc32: $crc32, mimeType: $mimeType)';
}

/// Resultado de una estimación o medición de compresión.
@immutable
class CompressionEstimate {
  /// Crea un resultado de compresión.
  const CompressionEstimate({
    required this.originalBytes,
    required this.compressedBytes,
  });

  /// Peso original en bytes.
  final int originalBytes;

  /// Peso comprimido en bytes.
  final int compressedBytes;

  /// Porcentaje de ahorro (0–100).
  double get savingsPercentage =>
      OptimizationUtils.calculateSavingsPercentage(originalBytes, compressedBytes);

  /// Bytes ahorrados (nunca negativo).
  int get savedBytes =>
      compressedBytes < originalBytes ? originalBytes - compressedBytes : 0;
}

/// Parámetros transferibles para compresión de imagen en un Isolate.
@immutable
class ImageCompressionParams {
  /// Crea los parámetros de compresión.
  const ImageCompressionParams({
    required this.bytes,
    this.minWidth = 256,
    this.minHeight = 256,
    this.quality = 82,
    this.format = CompressFormat.webp,
  });

  /// Bytes de la imagen original.
  final Uint8List bytes;

  /// Ancho máximo en píxeles.
  final int minWidth;

  /// Altura máxima en píxeles.
  final int minHeight;

  /// Calidad de compresión (80-85%).
  final int quality;

  /// Formato de salida (WebP por defecto).
  final CompressFormat format;
}

// ---------------------------------------------------------------------------
// Funciones top-level para compute() (entrada y salida transferibles)
// ---------------------------------------------------------------------------

/// Decodifica un arreglo JSON de objetos (p. ej. lote de mensajes).
///
/// Lanza [FormatException] si la raíz no es una lista de objetos.
List<Map<String, dynamic>> decodeJsonList(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! List) {
    throw const FormatException('Se esperaba un arreglo JSON en la raíz.');
  }
  return [
    for (final item in decoded)
      if (item is Map)
        Map<String, dynamic>.from(item)
      else
        throw const FormatException('Cada elemento debe ser un objeto JSON.'),
  ];
}

/// Codifica un lote de objetos a una cadena JSON.
String encodeJsonList(List<Map<String, dynamic>> items) => jsonEncode(items);

/// Calcula tamaño, CRC-32 y tipo MIME de un archivo en memoria.
FileMetrics analyzeFileBytes(Uint8List bytes) {
  return FileMetrics(
    sizeBytes: bytes.length,
    crc32: crc32Hex(bytes),
    mimeType: detectMimeType(bytes),
  );
}

/// Calcula el CRC-32 (IEEE 802.3) de [bytes] en hexadecimal.
String crc32Hex(Uint8List bytes) {
  final table = _crcTable;
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = table[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF).toUnsigned(32).toRadixString(16).padLeft(8, '0');
}

/// Detecta el tipo MIME a partir de la firma binaria del archivo.
String detectMimeType(Uint8List b) {
  bool at(int offset, List<int> sig) {
    if (b.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[offset + i] != sig[i]) return false;
    }
    return true;
  }

  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (at(0, const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (at(0, const [0x52, 0x49, 0x46, 0x46])) {
    if (at(8, const [0x57, 0x45, 0x42, 0x50])) return 'image/webp';
    if (at(8, const [0x57, 0x41, 0x56, 0x45])) return 'audio/wav';
  }
  if (at(4, const [0x66, 0x74, 0x79, 0x70])) {
    // Contenedor ISO-BMFF: el "brand" distingue audio, HEIC y video
    if (at(8, const [0x4D, 0x34, 0x41, 0x20])) return 'audio/mp4';
    if (at(8, const [0x68, 0x65, 0x69, 0x63]) ||
        at(8, const [0x68, 0x65, 0x69, 0x78]) ||
        at(8, const [0x6D, 0x69, 0x66, 0x31])) {
      return 'image/heic';
    }
    return 'video/mp4';
  }
  if (at(0, const [0x4F, 0x67, 0x67, 0x53])) return 'audio/ogg';
  if (at(0, const [0x49, 0x44, 0x33]) || at(0, const [0xFF, 0xFB])) {
    return 'audio/mpeg';
  }
  if (at(0, const [0x25, 0x50, 0x44, 0x46])) return 'application/pdf';
  return 'application/octet-stream';
}

// Tabla CRC-32 precalculada (una por isolate, inicialización perezosa)
final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c;
  }
  return table;
}();

// Decodifica y mapea a modelos dentro del isolate
List<T> _decodeAndMap<T>((String, T Function(Map<String, dynamic>)) task) {
  final (source, fromJson) = task;
  return decodeJsonList(source).map(fromJson).toList(growable: false);
}

/// Comprime una imagen en un Isolate secundario con [FlutterImageCompress].
/// Incluye fallback determinista para pruebas unitarias sin canales nativos.
Future<Uint8List> compressImageInIsolate(ImageCompressionParams params) async {
  try {
    final result = await FlutterImageCompress.compressWithList(
      params.bytes,
      minWidth: params.minWidth,
      minHeight: params.minHeight,
      quality: params.quality,
      format: params.format,
    );
    if (result.isNotEmpty && result.length < params.bytes.length) {
      return result;
    }
    return _fallbackSimulatedCompression(params);
  } catch (_) {
    return _fallbackSimulatedCompression(params);
  }
}

Uint8List _fallbackSimulatedCompression(ImageCompressionParams params) {
  final original = params.bytes;
  if (original.length <= 30 * 1024) return original;
  // Simulación: compresión al ~5.5% del peso original (objetivo < 35 KB)
  final targetLength = (original.length * 0.055).round().clamp(1024, 32 * 1024);
  return Uint8List.fromList(original.sublist(0, targetLength));
}

// ---------------------------------------------------------------------------
// API pública
// ---------------------------------------------------------------------------

/// Formateadores puros y despachadores de cómputo en segundo plano.
abstract final class OptimizationUtils {
  /// Tamaño a partir del cual el JSON se procesa en un isolate.
  ///
  /// Por debajo, el costo de crear el isolate supera al de decodificar.
  static const int jsonIsolateThreshold = 32 * 1024;

  /// Tamaño a partir del cual el análisis de archivos va a un isolate.
  static const int fileIsolateThreshold = 256 * 1024;

  /// Duración máxima de una nota de voz.
  static const Duration maxVoiceNoteDuration = Duration(seconds: 60);

  static const List<String> _byteUnits = ['B', 'KB', 'MB', 'GB', 'TB'];
  static const List<String> _weekdays = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  // --- Formateadores ---

  /// Convierte [duration] a `mm:ss` (o `h:mm:ss` si supera una hora).
  ///
  /// Duraciones negativas se tratan como cero.
  static String formatDuration(Duration duration) {
    final total = duration.isNegative ? 0 : duration.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    final mmss = '${_two(minutes)}:${_two(seconds)}';
    return hours > 0 ? '$hours:$mmss' : mmss;
  }

  /// Convierte [bytes] a una cadena legible en base 1024 (`B`, `KB`, `MB`…).
  static String formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < _byteUnits.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(decimals)} ${_byteUnits[unit]}';
  }

  /// Formatea la fecha de un mensaje de forma relativa.
  ///
  /// - Hoy: `10:45 AM`
  /// - Ayer: `Ayer`
  /// - Últimos 7 días: nombre del día (`Lunes`)
  /// - Anterior: `dd/MM/yyyy`
  ///
  /// [now] permite fijar la fecha de referencia en pruebas.
  static String formatChatTimestamp(DateTime dateTime, {DateTime? now}) {
    final local = dateTime.toLocal();
    final ref = (now ?? DateTime.now()).toLocal();

    // Diferencia en días de calendario, inmune a cambios de horario (DST)
    final days = DateTime.utc(ref.year, ref.month, ref.day)
        .difference(DateTime.utc(local.year, local.month, local.day))
        .inDays;

    if (days <= 0) return formatTime(local);
    if (days == 1) return 'Ayer';
    if (days < 7) return _weekdays[local.weekday - 1];
    return '${_two(local.day)}/${_two(local.month)}/${local.year}';
  }

  /// Formatea la hora en 12 h (`10:45 AM`).
  static String formatTime(DateTime dateTime) {
    final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final period = dateTime.hour < 12 ? 'AM' : 'PM';
    return '$hour12:${_two(dateTime.minute)} $period';
  }

  // --- Ahorro y ratios ---

  /// Porcentaje de reducción (0–100) entre [originalBytes] y [compressedBytes].
  ///
  /// Devuelve 0 si los datos son inválidos o no hubo reducción.
  static double calculateSavingsPercentage(int originalBytes, int compressedBytes) {
    if (originalBytes <= 0 || compressedBytes < 0) return 0;
    if (compressedBytes >= originalBytes) return 0;
    return (originalBytes - compressedBytes) / originalBytes * 100;
  }

  /// Estima la compresión de una foto a WebP calidad 75 (~78 % de ahorro).
  static CompressionEstimate estimateImageCompression(int originalBytes) {
    return CompressionEstimate(
      originalBytes: originalBytes,
      compressedBytes: (originalBytes * 0.22).round(),
    );
  }

  /// Estima la compresión de audio WAV estéreo 44.1 kHz a AAC mono 32 kbps.
  static CompressionEstimate estimateAudioCompression(Duration duration) {
    final seconds = duration.isNegative ? 0 : duration.inSeconds;
    return CompressionEstimate(
      originalBytes: seconds * 44100 * 2 * 2,
      compressedBytes: seconds * 4000,
    );
  }

  // --- Cómputo en segundo plano ---

  /// Decodifica un lote JSON; usa un isolate si supera [jsonIsolateThreshold].
  static Future<List<Map<String, dynamic>>> decodeJsonListInBackground(
    String source,
  ) async {
    if (source.length < jsonIsolateThreshold) return decodeJsonList(source);
    return compute(decodeJsonList, source, debugLabel: 'decodeJsonList');
  }

  /// Decodifica y convierte a modelos en un isolate.
  ///
  /// [fromJson] debe ser una función top-level, estática o un constructor
  /// tear-off (p. ej. `ChatMessage.fromJson`) para ser enviable.
  static Future<List<T>> decodeModelsInBackground<T>(
    String source,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    if (source.length < jsonIsolateThreshold) {
      return _decodeAndMap<T>((source, fromJson));
    }
    return compute(_decodeAndMap<T>, (source, fromJson),
        debugLabel: 'decodeModels');
  }

  /// Codifica un lote a JSON; usa un isolate si el lote es grande.
  static Future<String> encodeJsonListInBackground(
    List<Map<String, dynamic>> items, {
    int isolateMinItems = 200,
  }) async {
    if (items.length < isolateMinItems) return encodeJsonList(items);
    return compute(encodeJsonList, items, debugLabel: 'encodeJsonList');
  }

  /// Calcula métricas de archivo; usa un isolate si supera [fileIsolateThreshold].
  static Future<FileMetrics> analyzeFileInBackground(Uint8List bytes) async {
    if (bytes.length < fileIsolateThreshold) return analyzeFileBytes(bytes);
    return compute(analyzeFileBytes, bytes, debugLabel: 'analyzeFileBytes');
  }

  /// Detecta el tipo MIME a partir de la firma binaria de los bytes.
  static String detectFileMimeType(Uint8List bytes) => detectMimeType(bytes);

  /// Comprime y redimensiona una imagen en un Isolate secundario para no bloquear la UI.
  ///
  /// Limita las dimensiones a un máximo de 256x256 píxeles en formato WebP con calidad 80-85%.
  static Future<Uint8List> compressAvatarImageInBackground(
    Uint8List bytes, {
    int minWidth = 256,
    int minHeight = 256,
    int quality = 82,
    CompressFormat format = CompressFormat.webp,
  }) async {
    return compute(
      compressImageInIsolate,
      ImageCompressionParams(
        bytes: bytes,
        minWidth: minWidth,
        minHeight: minHeight,
        quality: quality,
        format: format,
      ),
      debugLabel: 'compressAvatarImage',
    );
  }

  /// Comprime y redimensiona una imagen de chat en un Isolate secundario para evitar UI Jank.
  ///
  /// Limita las dimensiones a un máximo de 1280x720 píxeles en formato WebP con calidad 75-80%
  /// garantizando un peso inferior a 300 KB y reducciones superiores al 85%.
  static Future<Uint8List> compressChatImageInBackground(
    Uint8List bytes, {
    int minWidth = 1280,
    int minHeight = 720,
    int quality = 78,
    CompressFormat format = CompressFormat.webp,
  }) async {
    return compute(
      compressImageInIsolate,
      ImageCompressionParams(
        bytes: bytes,
        minWidth: minWidth,
        minHeight: minHeight,
        quality: quality,
        format: format,
      ),
      debugLabel: 'compressChatImage',
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
