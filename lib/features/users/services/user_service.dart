import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';

/// Servicio de gestión de perfiles y búsqueda exacta de usuarios.
class UserService extends ChangeNotifier {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  // Simulación de directorio de usuarios registrados en Supabase
  final List<UserProfile> _registeredUsers = [
    UserProfile(
      id: 'usr_001',
      username: 'usuario1',
      fullName: 'Carlos Santana',
      bio: 'Desarrollador móvil | Amante del café',
      avatarUrl: null,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
      isOnline: true,
    ),
    UserProfile(
      id: 'usr_002',
      username: 'maria_dev',
      fullName: 'María González',
      bio: 'Ingeniería de Software',
      avatarUrl: null,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
      isOnline: true,
    ),
    UserProfile(
      id: 'usr_003',
      username: 'alexis',
      fullName: 'Alexis Miranda',
      bio: 'En línea',
      avatarUrl: null,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      isOnline: false,
    ),
  ];

  /// Realiza la búsqueda de un usuario mediante coincidencia exacta de "Nombre de Usuario" (Must Have).
  Future<UserProfile?> searchByExactUsername(String query) async {
    final sanitizedQuery = query.trim().toLowerCase();
    if (sanitizedQuery.isEmpty) return null;

    // Simula tiempo de red a Supabase PostgreSQL
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      // Coincidencia estricta y exacta
      final match = _registeredUsers.firstWhere(
        (user) => user.username.toLowerCase() == sanitizedQuery,
      );
      return match;
    } catch (_) {
      // No hubo coincidencia exacta
      return null;
    }
  }

  /// Retorna la lista de usuarios simulados para pruebas de directorio.
  List<UserProfile> getAllUsersForDemo() => List.unmodifiable(_registeredUsers);
}
