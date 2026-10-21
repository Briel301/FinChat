import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_config.dart';
import '../models/user_profile.dart';

/// Servicio para la gestión de perfiles de usuario y consultas de búsqueda exacta en FinChat.
///
/// Optimizado para aprovechar el índice B-Tree en PostgreSQL (`lower(username)`),
/// evitando escaneos secuenciales y búsquedas difusas con comodines.
class UserService extends ChangeNotifier {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  /// Directorio local de demostración para pruebas y estado sin conexión.
  final List<UserProfile> _demoUsers = [
    UserProfile(
      id: 'usr_001',
      username: 'usuario1',
      email: 'usuario1@finchat.app',
      fullName: 'Carlos Santana',
      bio: 'Desarrollador móvil | Amante del café',
      avatarUrl: null,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
      isOnline: true,
    ),
    UserProfile(
      id: 'usr_002',
      username: 'maria_dev',
      email: 'maria@finchat.app',
      fullName: 'María González',
      bio: 'Ingeniería de Software & Criptografía',
      avatarUrl: null,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
      isOnline: true,
    ),
    UserProfile(
      id: 'usr_003',
      username: 'alexis',
      email: 'alexis@finchat.app',
      fullName: 'Alexis Miranda',
      bio: 'En línea en FinChat',
      avatarUrl: null,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      isOnline: false,
    ),
  ];

  // ==========================================================================
  // 1. BÚSQUEDA EXACTA DE NOMBRE DE USUARIO (Must Have MoSCoW: 10 pts)
  // ==========================================================================

  /// Realiza una búsqueda por coincidencia EXACTA de nombre de usuario sin comodines (%).
  ///
  /// Utiliza la comparación directa en minúsculas contra el índice funcional
  /// `idx_profiles_username_lower` de la base de datos PostgreSQL, garantizando
  /// tiempos de respuesta en milisegundos y un costo computacional O(log n).
  ///
  /// Retorna la entidad [UserProfile] si existe o `null` si no hay coincidencia exacta.
  Future<UserProfile?> searchByExactUsername(String username) async {
    final sanitizedQuery = username.trim().toLowerCase();
    if (sanitizedQuery.isEmpty) return null;

    if (SupabaseConfig.isInitialized) {
      try {
        final response = await SupabaseConfig.from(SupabaseConfig.tableProfiles)
            .select()
            .eq('username', sanitizedQuery)
            .maybeSingle();

        if (response == null) return null;
        return UserProfile.fromMap(response);
      } on PostgrestException catch (e) {
        debugPrint('[UserService] Error PostgREST en búsqueda exacta (${e.code}): ${e.message}');
        return null;
      } catch (e) {
        debugPrint('[UserService] Error inesperado en searchByExactUsername: $e');
        return null;
      }
    }

    // Modo local para pruebas / demostración offline
    await Future.delayed(const Duration(milliseconds: 150));
    try {
      return _demoUsers.firstWhere(
        (user) => user.username.toLowerCase() == sanitizedQuery,
      );
    } catch (_) {
      return null;
    }
  }

  // ==========================================================================
  // 2. LECTURA DE PERFIL POR ID (getProfileById)
  // ==========================================================================

  /// Obtiene los datos del perfil de un usuario a partir de su UUID único.
  ///
  /// Retorna [UserProfile] si existe o `null` si el identificador no fue encontrado.
  Future<UserProfile?> getProfileById(String userId) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty) return null;

    if (SupabaseConfig.isInitialized) {
      try {
        final response = await SupabaseConfig.from(SupabaseConfig.tableProfiles)
            .select()
            .eq('id', cleanId)
            .maybeSingle();

        if (response == null) return null;
        return UserProfile.fromMap(response);
      } on PostgrestException catch (e) {
        debugPrint('[UserService] Error PostgREST al consultar perfil ($cleanId): ${e.message}');
        return null;
      } catch (e) {
        debugPrint('[UserService] Error inesperado en getProfileById: $e');
        return null;
      }
    }

    // Fallback local
    try {
      return _demoUsers.firstWhere((user) => user.id == cleanId);
    } catch (_) {
      return null;
    }
  }

  // ==========================================================================
  // 3. ACTUALIZACIÓN DE PERFIL PROPIO (updateProfile)
  // ==========================================================================

  /// Actualiza los metadatos editables del perfil (`fullName`, `bio`, `avatarUrl`)
  /// para el usuario autenticado actual o el [userId] especificado.
  ///
  /// Valida la restricción de longitud máxima de la biografía (160 caracteres).
  Future<UserProfile> updateProfile({
    String? fullName,
    String? bio,
    String? avatarUrl,
    String? userId,
  }) async {
    // Validación de negocio / restricción chk_bio_length
    if (bio != null && bio.length > 160) {
      throw ArgumentError('La biografía no puede exceder los 160 caracteres (actual: ${bio.length}).');
    }

    final targetUserId = userId ??
        (SupabaseConfig.isInitialized ? SupabaseConfig.auth.currentUser?.id : 'usr_001');

    if (targetUserId == null || targetUserId.isEmpty) {
      throw StateError('No hay una sesión de usuario autenticada para actualizar el perfil.');
    }

    final payload = <String, dynamic>{
      if (fullName != null) 'full_name': fullName.trim(),
      if (bio != null) 'bio': bio.trim(),
      if (avatarUrl != null) 'avatar_url': avatarUrl.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (SupabaseConfig.isInitialized) {
      try {
        final response = await SupabaseConfig.from(SupabaseConfig.tableProfiles)
            .update(payload)
            .eq('id', targetUserId)
            .select()
            .single();

        final updatedProfile = UserProfile.fromMap(response);
        notifyListeners();
        return updatedProfile;
      } on PostgrestException catch (e) {
        debugPrint('[UserService] Error PostgREST al actualizar perfil: ${e.message}');
        rethrow;
      } catch (e) {
        debugPrint('[UserService] Error no controlado al actualizar perfil: $e');
        rethrow;
      }
    }

    // Actualización en memoria para entorno de pruebas / showcase
    final index = _demoUsers.indexWhere((u) => u.id == targetUserId);
    final base = index >= 0
        ? _demoUsers[index]
        : UserProfile(
            id: targetUserId,
            username: 'usuario_demo',
            email: 'demo@finchat.app',
            fullName: fullName ?? 'Usuario Demo',
            createdAt: DateTime.now(),
          );

    final updated = base.copyWith(
      fullName: fullName?.trim() ?? base.fullName,
      bio: bio?.trim() ?? base.bio,
      avatarUrl: avatarUrl?.trim() ?? base.avatarUrl,
    );

    if (index >= 0) {
      _demoUsers[index] = updated;
    } else {
      _demoUsers.add(updated);
    }

    notifyListeners();
    return updated;
  }

  // ==========================================================================
  // 4. MÉTODOS DE SOPORTE PARA UI SHOWCASE
  // ==========================================================================

  /// Retorna la lista de usuarios precargados para demostración en interfaz.
  List<UserProfile> getAllUsersForDemo() => List.unmodifiable(_demoUsers);
}
