import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user_session.dart';

/// Servicio de Autenticación con soporte MFA para Supabase Auth.
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  UserSession _currentSession = UserSession.empty();
  String? _expectedMfaCode; // Simulado para validación interactiva inmediata

  UserSession get currentSession => _currentSession;
  bool get isLoggedIn => _currentSession.isAuthenticated;

  /// Registra un nuevo usuario sin requerir teléfono ni SIM.
  Future<bool> register({
    required String username,
    required String email,
    required String password,
    String? fullName,
  }) async {
    // Simula llamada asíncrona a Supabase Auth
    await Future.delayed(const Duration(milliseconds: 600));

    _currentSession = UserSession(
      userId: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      email: email,
      username: username.toLowerCase().trim(),
      fullName: fullName ?? username,
      isMfaRequired: true,
      isMfaVerified: false,
    );

    // Genera código MFA inicial
    _expectedMfaCode = '123456';
    notifyListeners();
    return true;
  }

  /// Inicia sesión y prepara el reto MFA (Doble Factor).
  Future<bool> signIn({
    required String identifier, // username o correo
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final isEmail = identifier.contains('@');
    final username = isEmail ? identifier.split('@').first : identifier;

    _currentSession = UserSession(
      userId: 'usr_demo_101',
      email: isEmail ? identifier : '$identifier@finchat.app',
      username: username.toLowerCase().trim(),
      fullName: 'Usuario Demo ($username)',
      isMfaRequired: true,
      isMfaVerified: false,
      token: 'jwt_mock_token_supabase',
    );

    _expectedMfaCode = '123456'; // Código demostrativo OTP
    notifyListeners();
    return true;
  }

  /// Verifica el código MFA ingresado por el usuario.
  Future<bool> verifyMfaCode(String code) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (code.trim() == _expectedMfaCode || code.trim() == '123456') {
      _currentSession = _currentSession.copyWith(isMfaVerified: true);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Cierra la sesión activa.
  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _currentSession = UserSession.empty();
    _expectedMfaCode = null;
    notifyListeners();
  }
}
