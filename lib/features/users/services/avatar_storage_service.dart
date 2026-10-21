import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_config.dart';
import '../../../core/utils/optimization_utils.dart';
import 'user_service.dart';

/// Resultado detallado de la compresión y subida de avatar.
@immutable
class AvatarUploadResult {
  /// URL pública directa para consumir el avatar desde la CDN de Supabase Storage.
  final String publicUrl;

  /// Ruta relativa normalizada dentro del bucket `avatars` (ej. `${userId}.webp`).
  final String storagePath;

  /// Peso en bytes de la imagen original capturada por la cámara o galería.
  final int originalSizeBytes;

  /// Peso en bytes de la imagen optimizada WebP a 256x256 píxeles.
  final int compressedSizeBytes;

  /// Porcentaje de ahorro de bytes (> 90% respecto a la original).
  final double savingsPercentage;

  /// Indica si la operación sobreescribió atómicamente la imagen previa (`upsert: true`).
  final bool isUpsert;

  const AvatarUploadResult({
    required this.publicUrl,
    required this.storagePath,
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
    required this.savingsPercentage,
    this.isUpsert = true,
  });

  /// Indica si la imagen optimizada cumple con el objetivo de arquitectura (< 35 KB).
  bool get meetsSizeTarget => compressedSizeBytes <= 35 * 1024;

  @override
  String toString() =>
      'AvatarUploadResult(path: $storagePath, original: ${OptimizationUtils.formatBytes(originalSizeBytes)}, '
      'comprimido: ${OptimizationUtils.formatBytes(compressedSizeBytes)}, ahorro: ${savingsPercentage.toStringAsFixed(1)}%)';
}

/// Servicio de optimización, compresión en Isolates y persistencia de avatares en Supabase Storage.
///
/// Previene la saturación del ancho de banda y la fuga de memoria al comprimir a WebP 256x256
/// antes de subir, sobreescribiendo mediante `upsert: true` para evitar archivos huérfanos.
class AvatarStorageService {
  final ImagePicker _picker;
  final UserService _userService;
  final SupabaseStorageClient? _customStorage;

  /// Constructor con inyección de dependencias para facilitar testing y desacoplamiento.
  AvatarStorageService({
    ImagePicker? picker,
    UserService? userService,
    SupabaseStorageClient? customStorage,
  })  : _picker = picker ?? ImagePicker(),
        _userService = userService ?? UserService(),
        _customStorage = customStorage;

  SupabaseStorageClient get _storage {
    if (_customStorage != null) return _customStorage!;
    if (SupabaseConfig.isInitialized) return SupabaseConfig.storage;
    throw StateError('Supabase Storage no está inicializado.');
  }

  // ==========================================================================
  // 1. GESTIÓN DEL BUCKET Y PERMISOS PÚBLICOS
  // ==========================================================================

  /// Configura o verifica que el bucket `avatars` exista con política de lectura pública.
  Future<void> ensureAvatarBucketExists() async {
    if (!SupabaseConfig.isInitialized && _customStorage == null) return;

    try {
      await _storage.createBucket(
        SupabaseConfig.bucketAvatars,
        const BucketOptions(public: true),
      );
      debugPrint('[AvatarStorageService] Bucket "${SupabaseConfig.bucketAvatars}" verificado como público.');
    } on StorageException catch (e) {
      // Ignorar si el bucket ya existe (código 409 o mensaje 'already exists')
      if (e.statusCode != '409' && !e.message.toLowerCase().contains('already exists')) {
        debugPrint('[AvatarStorageService] Aviso sobre bucket avatars: ${e.message}');
      }
    } catch (e) {
      debugPrint('[AvatarStorageService] Verificación de bucket omitida: $e');
    }
  }

  // ==========================================================================
  // 2. SELECCIÓN DE IMAGEN (image_picker)
  // ==========================================================================

  /// Permite al usuario capturar una fotografía o elegir una imagen de la galería.
  ///
  /// Retorna un [XFile] con la imagen seleccionada o `null` si el usuario cancela.
  Future<XFile?> pickAvatarImage({
    ImageSource source = ImageSource.gallery,
    int? imageQuality,
  }) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: imageQuality,
      );
      return pickedFile;
    } catch (e) {
      debugPrint('[AvatarStorageService] Error al seleccionar imagen con image_picker: $e');
      return null;
    }
  }

  // ==========================================================================
  // 3. COMPRESIÓN Y REDIMENSIONAMIENTO EN ISOLATE SECUNDARIO (compute())
  // ==========================================================================

  /// Comprime los bytes crudos de una imagen redimensionándola a un máximo de 256x256
  /// píxeles en formato WebP con calidad del 80-85%.
  ///
  /// Se ejecuta en un Isolate secundario a través de [OptimizationUtils] para garantizar 60 fps
  /// constantes sin congelar el hilo principal de la UI.
  Future<Uint8List> compressAvatarBytes(Uint8List rawBytes) async {
    return OptimizationUtils.compressAvatarImageInBackground(
      rawBytes,
      minWidth: 256,
      minHeight: 256,
      quality: 82,
      format: CompressFormat.webp,
    );
  }

  // ==========================================================================
  // 4. SUBIDA ATÓMICA UPSERT Y ACTUALIZACIÓN EN PERFIL
  // ==========================================================================

  /// Sube la imagen comprimida a Supabase Storage con patrón `upsert: true`
  /// bajo el nombre normalizado `${userId}.webp`.
  ///
  /// Actualiza automáticamente la columna `avatar_url` en la tabla `profiles`
  /// del usuario a través de [UserService].
  Future<AvatarUploadResult> uploadProcessedAvatar({
    required String userId,
    required Uint8List rawBytes,
    Uint8List? preCompressedBytes,
  }) async {
    final cleanUserId = userId.trim();
    if (cleanUserId.isEmpty) {
      throw ArgumentError('El userId no puede estar vacío.');
    }

    final originalSize = rawBytes.length;

    // 1. Comprimir en isolate si no se proveyeron bytes pre-procesados
    final compressedBytes = preCompressedBytes ?? await compressAvatarBytes(rawBytes);
    final compressedSize = compressedBytes.length;

    // 2. Calcular porcentaje de ahorro real (> 90% objetivo)
    final savings = OptimizationUtils.calculateSavingsPercentage(originalSize, compressedSize);

    // 3. Nombre normalizado del archivo: {userId}.webp dentro del bucket 'avatars'
    final normalizedFileName = '$cleanUserId.webp';
    String publicUrl;

    if (SupabaseConfig.isInitialized || _customStorage != null) {
      try {
        await _storage.from(SupabaseConfig.bucketAvatars).uploadBinary(
          normalizedFileName,
          compressedBytes,
          fileOptions: const FileOptions(
            upsert: true, // Reemplazo atómico sin dejar archivos basura huérfanos
            contentType: 'image/webp',
          ),
        );

        // Obtener la URL pública desde la CDN
        publicUrl = _storage.from(SupabaseConfig.bucketAvatars).getPublicUrl(normalizedFileName);

        // Actualizar URL en la tabla profiles de PostgreSQL
        await _userService.updateProfile(
          avatarUrl: publicUrl,
          userId: cleanUserId,
        );
      } on StorageException catch (e) {
        debugPrint('[AvatarStorageService] Error Storage (${e.statusCode}): ${e.message}');
        rethrow;
      } catch (e) {
        debugPrint('[AvatarStorageService] Error al subir avatar: $e');
        rethrow;
      }
    } else {
      // Modo local / prueba desconectada
      publicUrl = 'https://supabase.co/storage/v1/object/public/${SupabaseConfig.bucketAvatars}/$normalizedFileName';
      await _userService.updateProfile(
        avatarUrl: publicUrl,
        userId: cleanUserId,
      );
    }

    return AvatarUploadResult(
      publicUrl: publicUrl,
      storagePath: '${SupabaseConfig.bucketAvatars}/$normalizedFileName',
      originalSizeBytes: originalSize,
      compressedSizeBytes: compressedSize,
      savingsPercentage: savings,
      isUpsert: true,
    );
  }

  // ==========================================================================
  // 5. FLUJO INTEGRAL ORQUESTADO
  // ==========================================================================

  /// Flujo completo para el usuario:
  /// 1. Selecciona imagen con [ImagePicker] (Cámara o Galería).
  /// 2. Lee y procesa en un Isolate secundario con WebP 256x256.
  /// 3. Sube con `upsert: true` a Supabase Storage `avatars/${userId}.webp`.
  /// 4. Actualiza `avatar_url` en PostgreSQL y retorna el resultado.
  Future<AvatarUploadResult?> pickCompressAndUploadAvatar({
    required String userId,
    ImageSource source = ImageSource.gallery,
  }) async {
    final pickedFile = await pickAvatarImage(source: source);
    if (pickedFile == null) return null;

    final rawBytes = await pickedFile.readAsBytes();
    return uploadProcessedAvatar(
      userId: userId,
      rawBytes: rawBytes,
    );
  }
}
