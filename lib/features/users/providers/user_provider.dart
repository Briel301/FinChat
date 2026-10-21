import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/avatar_storage_service.dart';
import '../services/user_service.dart';

/// Proveedor de estado para la gestión del perfil del usuario y búsqueda en el directorio.
class UserProvider extends ChangeNotifier {
  final UserService _userService;
  final AvatarStorageService _avatarStorageService;

  UserProfile? _currentUserProfile;
  UserProfile? _searchResult;
  bool _isSearching = false;
  bool _hasSearched = false;
  bool _isUpdating = false;
  String? _errorMessage;

  UserProvider({
    UserService? userService,
    AvatarStorageService? avatarStorageService,
  })  : _userService = userService ?? UserService(),
        _avatarStorageService = avatarStorageService ?? AvatarStorageService();

  // ==========================================================================
  // GETTERS DE ESTADO
  // ==========================================================================

  UserProfile? get currentUserProfile => _currentUserProfile;
  UserProfile? get searchResult => _searchResult;
  bool get isSearching => _isSearching;
  bool get hasSearched => _hasSearched;
  bool get isUpdating => _isUpdating;
  String? get errorMessage => _errorMessage;

  /// Lista de usuarios precargados para demostración interactiva en la UI.
  List<UserProfile> get demoUsers => _userService.getAllUsersForDemo();

  // ==========================================================================
  // 1. BÚSQUEDA EXACTA DE USUARIO (Must Have MoSCoW: 10 pts)
  // ==========================================================================

  /// Ejecuta la consulta a PostgreSQL forzando coincidencia EXACTA de nombre de usuario.
  Future<UserProfile?> searchUser(String username) async {
    final cleanQuery = username.trim();
    if (cleanQuery.isEmpty) {
      _searchResult = null;
      _hasSearched = true;
      _isSearching = false;
      notifyListeners();
      return null;
    }

    _isSearching = true;
    _hasSearched = true;
    _searchResult = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _userService.searchByExactUsername(cleanQuery);
      _searchResult = user;
      _isSearching = false;
      notifyListeners();
      return user;
    } catch (e) {
      _errorMessage = 'Error al buscar usuario: $e';
      _isSearching = false;
      notifyListeners();
      return null;
    }
  }

  /// Limpia el estado de búsqueda actual.
  void clearSearch() {
    _searchResult = null;
    _hasSearched = false;
    _isSearching = false;
    _errorMessage = null;
    notifyListeners();
  }

  // ==========================================================================
  // 2. GESTIÓN DEL PERFIL PROPIO
  // ==========================================================================

  /// Carga el perfil del usuario actual por su UUID.
  Future<UserProfile?> loadUserProfile(String userId) async {
    try {
      final profile = await _userService.getProfileById(userId);
      if (profile != null) {
        _currentUserProfile = profile;
        notifyListeners();
      }
      return profile;
    } catch (e) {
      _errorMessage = 'Error al cargar perfil: $e';
      notifyListeners();
      return null;
    }
  }

  /// Actualiza la biografía del usuario (máximo 160 caracteres).
  Future<bool> updateBio(String bio, {String? userId}) async {
    final cleanBio = bio.trim();
    if (cleanBio.length > 160) {
      _errorMessage = 'La biografía no puede superar los 160 caracteres.';
      notifyListeners();
      return false;
    }

    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final targetId = userId ?? _currentUserProfile?.id;
      final updated = await _userService.updateProfile(
        bio: cleanBio,
        userId: targetId,
      );
      _currentUserProfile = updated;
      _isUpdating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Error al actualizar biografía: $e';
      _isUpdating = false;
      notifyListeners();
      return false;
    }
  }

  /// Actualiza el nombre completo visible del usuario.
  Future<bool> updateFullName(String fullName, {String? userId}) async {
    final cleanName = fullName.trim();
    if (cleanName.isEmpty) return false;

    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final targetId = userId ?? _currentUserProfile?.id;
      final updated = await _userService.updateProfile(
        fullName: cleanName,
        userId: targetId,
      );
      _currentUserProfile = updated;
      _isUpdating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Error al actualizar nombre: $e';
      _isUpdating = false;
      notifyListeners();
      return false;
    }
  }

  /// Selecciona, comprime en Isolate (WebP < 35 KB) y sube el nuevo avatar a Supabase Storage.
  Future<AvatarUploadResult?> updateProfilePicture({
    required String userId,
    ImageSource source = ImageSource.gallery,
  }) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _avatarStorageService.pickCompressAndUploadAvatar(
        userId: userId,
        source: source,
      );

      if (result != null && _currentUserProfile != null) {
        _currentUserProfile = _currentUserProfile!.copyWith(
          avatarUrl: result.publicUrl,
        );
      }

      _isUpdating = false;
      notifyListeners();
      return result;
    } catch (e) {
      _errorMessage = 'Error al procesar y subir imagen: $e';
      _isUpdating = false;
      notifyListeners();
      return null;
    }
  }

  /// Limpia cualquier mensaje de error activo.
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
