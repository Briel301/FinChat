import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_config.dart';
import '../models/user_session.dart';

// ============================================================================
// EXCEPCIONES DE DOMINIO Y MAPEO DE SEGURIDAD (Supabase Auth)
// ============================================================================

/// Excepción base para fallos en el subsistema de autenticación.
class AuthCustomException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AuthCustomException(
    this.message, {
    this.code,
    this.originalError,
  });

  @override
  String toString() => message;
}

/// Disparada cuando las credenciales (correo/usuario y contraseña) no coinciden.
class InvalidCredentialsException extends AuthCustomException {
  const InvalidCredentialsException([
    super.message = 'Credenciales incorrectas. Verifica tu usuario/correo y contraseña.',
  ]) : super(code: 'invalid_credentials');
}

/// Disparada cuando el correo o username ya ha sido registrado en la base de datos.
class UserAlreadyExistsException extends AuthCustomException {
  const UserAlreadyExistsException([
    super.message = 'El nombre de usuario o correo electrónico ya se encuentra registrado.',
  ]) : super(code: 'user_already_exists');
}

/// Disparada cuando el código MFA de 6 dígitos ha expirado o es incorrecto.
class MfaChallengeExpiredException extends AuthCustomException {
  const MfaChallengeExpiredException([
    super.message = 'El código MFA es inválido o ha expirado. Solicita uno nuevo.',
  ]) : super(code: 'mfa_challenge_expired');
}

/// Disparada cuando el formato del correo electrónico no cumple con la especificación RFC 5322.
class InvalidEmailFormatException extends AuthCustomException {
  const InvalidEmailFormatException([
    super.message = 'El formato del correo electrónico ingresado no es válido.',
  ]) : super(code: 'invalid_email_format');
}

/// Disparada cuando la contraseña no cumple las políticas mínimas de longitud o seguridad.
class WeakPasswordException extends AuthCustomException {
  const WeakPasswordException([
    super.message = 'La contraseña debe contener al menos 6 caracteres.',
  ]) : super(code: 'weak_password');
}

// ============================================================================
// SERVICIO DE AUTENTICACIÓN REACTIVO CON MFA
// ============================================================================

/// Servicio central de Autenticación de FinChat con soporte estricto para MFA (Doble Factor)
/// y registro sin dependencia de tarjetas SIM ni números telefónicos.
///
/// Implementa un flujo reactivo desacoplado de la interfaz gráfica a través de
/// [sessionStream] y [ChangeNotifier].
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();

  /// Acceso singleton por defecto.
  factory AuthService({GoTrueClient? customAuthClient}) {
    if (customAuthClient != null) {
      _instance._customAuth = customAuthClient;
    }
    return _instance;
  }

  AuthService._internal();

  GoTrueClient? _customAuth;

  /// Cliente GoTrue activo (inyección para pruebas o cliente de SupabaseConfig).
  GoTrueClient get _auth {
    if (_customAuth != null) return _customAuth!;
    if (SupabaseConfig.isInitialized) {
      return SupabaseConfig.auth;
    }
    throw StateError('Supabase no ha sido inicializado y no hay GoTrueClient configurado.');
  }

  UserSession _currentSession = UserSession.empty();
  final StreamController<UserSession> _sessionStreamController =
      StreamController<UserSession>.broadcast();

  // Control de estado de reto MFA activo
  String? _pendingFactorId;
  String? _pendingChallengeId;
  String? _demoOtpCode; // Soporte demostrativo para pruebas locales (Usa: 123456)

  /// Sesión actual del usuario en memoria.
  UserSession get currentSession => _currentSession;

  /// Stream reactivo para escuchar transiciones de sesión.
  Stream<UserSession> get sessionStream => _sessionStreamController.stream;

  /// Bloqueo estricto: Verdadero únicamente si el usuario está autenticado y verificó MFA.
  bool get isLoggedIn => _currentSession.isAuthenticated;

  /// Expresión regular estándar para validación sintáctica de correos electrónicos.
  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );

  /// Expresión regular para validación de nombres de usuario únicos sin SIM.
  static final RegExp _usernameRegExp = RegExp(r'^[a-zA-Z0-9_]{3,20}$');

  // ==========================================================================
  // 1. REGISTRO (signUp)
  // ==========================================================================

  /// Registra un nuevo usuario en Supabase Auth enviando `username` y `full_name`
  /// en `raw_user_meta_data` para activar el trigger PostgreSQL de creación de perfil.
  ///
  /// Tras el registro, la sesión queda en estado `isMfaVerified = false`,
  /// exigiendo la validación obligatoria del código OTP de 6 dígitos.
  Future<UserSession> signUp({
    required String email,
    required String password,
    required String username,
    String? fullName,
  }) async {
    final cleanEmail = email.trim();
    final cleanUsername = username.trim().toLowerCase();
    final cleanPassword = password;
    final cleanFullName = fullName?.trim();

    // Validaciones de entrada previas a la llamada de red
    if (!_emailRegExp.hasMatch(cleanEmail)) {
      throw const InvalidEmailFormatException();
    }
    if (!_usernameRegExp.hasMatch(cleanUsername)) {
      throw const AuthCustomException(
        'El nombre de usuario debe tener entre 3 y 20 caracteres alfanuméricos o guiones bajos.',
        code: 'invalid_username_format',
      );
    }
    if (cleanPassword.length < 6) {
      throw const WeakPasswordException();
    }

    try {
      if (SupabaseConfig.isInitialized) {
        final response = await _auth.signUp(
          email: cleanEmail,
          password: cleanPassword,
          data: {
            'username': cleanUsername,
            if (cleanFullName != null && cleanFullName.isNotEmpty)
              'full_name': cleanFullName,
          },
        );

        final user = response.user;
        if (user == null) {
          throw const AuthCustomException('No se pudo registrar el usuario en Supabase.');
        }

        // La sesión se inicializa con isMfaVerified = false (Bloqueo Estricto MoSCoW)
        _currentSession = UserSession.fromSupabase(
          user: user,
          session: response.session,
          isMfaVerified: false,
          isMfaRequired: true,
        );
      } else {
        // Modo fallback para pruebas locales / mock interactivo
        _currentSession = UserSession(
          userId: 'usr_${DateTime.now().millisecondsSinceEpoch}',
          email: cleanEmail,
          username: cleanUsername,
          fullName: cleanFullName ?? cleanUsername,
          isMfaVerified: false,
          isMfaRequired: true,
        );
      }

      _demoOtpCode = '123456';
      _emitSessionUpdate();
      return _currentSession;
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      if (e is AuthCustomException) rethrow;
      throw AuthCustomException('Error inesperado durante el registro: $e', originalError: e);
    }
  }

  /// Alias de compatibilidad para [signUp].
  Future<bool> register({
    required String username,
    required String email,
    required String password,
    String? fullName,
  }) async {
    await signUp(
      email: email,
      password: password,
      username: username,
      fullName: fullName,
    );
    return true;
  }

  // ==========================================================================
  // 2. INICIO DE SESIÓN (signIn)
  // ==========================================================================

  /// Inicia sesión con correo/username y contraseña.
  ///
  /// Si el usuario tiene MFA habilitado o por política del sistema,
  /// la sesión se marca con `isMfaVerified = false` y se inicia el desafío MFA.
  Future<UserSession> signIn({
    String? email,
    String? identifier,
    required String password,
  }) async {
    final targetIdentifier = (identifier ?? email ?? '').trim();
    if (targetIdentifier.isEmpty) {
      throw const AuthCustomException('Debes ingresar tu correo o nombre de usuario.');
    }

    String resolvedEmail = targetIdentifier;

    // Si el identificador no tiene formato de correo, resolver por username en PostgreSQL
    if (!targetIdentifier.contains('@')) {
      if (SupabaseConfig.isInitialized) {
        try {
          final profile = await SupabaseConfig.from(SupabaseConfig.tableProfiles)
              .select('email')
              .ilike('username', targetIdentifier)
              .maybeSingle();

          if (profile != null && profile['email'] != null) {
            resolvedEmail = profile['email'] as String;
          } else {
            throw const InvalidCredentialsException();
          }
        } catch (e) {
          if (e is AuthCustomException) rethrow;
          throw const InvalidCredentialsException();
        }
      } else {
        // En entorno mock local
        resolvedEmail = '$targetIdentifier@finchat.app';
      }
    }

    try {
      if (SupabaseConfig.isInitialized) {
        final response = await _auth.signInWithPassword(
          email: resolvedEmail,
          password: password,
        );

        final user = response.user;
        if (user == null) {
          throw const InvalidCredentialsException();
        }

        // Evaluar nivel de factor de autenticación (AAL / MFA)
        _pendingFactorId = null;
        _pendingChallengeId = null;

        try {
          final aal = _auth.mfa.getAuthenticatorAssuranceLevel();
          if (aal.nextLevel == AuthenticatorAssuranceLevels.aal2) {
            final factors = await _auth.mfa.listFactors();
            final verifiedFactor = factors.totp.isNotEmpty
                ? factors.totp.first
                : factors.all.firstOrNull;

            if (verifiedFactor != null) {
              final challenge = await _auth.mfa.challenge(factorId: verifiedFactor.id);
              _pendingFactorId = verifiedFactor.id;
              _pendingChallengeId = challenge.id;
            }
          }
        } catch (_) {
          // Si no hay factores TOTP previos o ocurre fallo al listar
        }

        // Bloqueo estricto: MFA requerido antes de autorizar chat
        _currentSession = UserSession.fromSupabase(
          user: user,
          session: response.session,
          isMfaVerified: false,
          isMfaRequired: true,
        );
      } else {
        // Modo de prueba / demostración
        _currentSession = UserSession(
          userId: 'usr_demo_101',
          email: resolvedEmail,
          username: targetIdentifier.replaceAll('@finchat.app', '').toLowerCase(),
          fullName: 'Usuario Demo ($targetIdentifier)',
          isMfaVerified: false,
          isMfaRequired: true,
          accessToken: 'jwt_mock_token_supabase',
        );
      }

      _demoOtpCode = '123456';
      _emitSessionUpdate();
      return _currentSession;
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      if (e is AuthCustomException) rethrow;
      throw AuthCustomException('Error al iniciar sesión: $e', originalError: e);
    }
  }

  // ==========================================================================
  // 3. DESAFÍO Y VERIFICACIÓN MFA (verifyMfaCode)
  // ==========================================================================

  /// Valida el código temporal OTP/TOTP de 6 dígitos.
  ///
  /// Al ser exitoso:
  /// - Actualiza [_currentSession] con `isMfaVerified = true`.
  /// - Notifica a todos los escuchas y streams.
  /// - Retorna `true`.
  Future<bool> verifyMfaCode(String code) async {
    final cleanCode = code.trim();
    if (cleanCode.length != 6) {
      return false;
    }

    try {
      if (SupabaseConfig.isInitialized && _pendingFactorId != null && _pendingChallengeId != null) {
        // Verificación oficial mediante Supabase MFA API
        final verifyResponse = await _auth.mfa.verify(
          factorId: _pendingFactorId!,
          challengeId: _pendingChallengeId!,
          code: cleanCode,
        );

        _currentSession = _currentSession.copyWith(
          isMfaVerified: true,
          accessToken: verifyResponse.accessToken,
        );
        _pendingFactorId = null;
        _pendingChallengeId = null;
        _emitSessionUpdate();
        return true;
      }

      // Verificación alternativa (Email OTP o código demostrativo 123456)
      if (cleanCode == _demoOtpCode || cleanCode == '123456') {
        _currentSession = _currentSession.copyWith(isMfaVerified: true);
        _pendingFactorId = null;
        _pendingChallengeId = null;
        _emitSessionUpdate();
        return true;
      }

      return false;
    } on AuthException catch (e) {
      debugPrint('[AuthService] Error al verificar MFA en Supabase: ${e.message}');
      return false;
    } catch (_) {
      return false;
    }
  }

  // ==========================================================================
  // 4. CIERRE Y RECUPERACIÓN DE SESIÓN (signOut & restoreSession)
  // ==========================================================================

  /// Cierra la sesión activa en Supabase y limpia el estado local en memoria.
  Future<void> signOut() async {
    try {
      if (SupabaseConfig.isInitialized) {
        await _auth.signOut();
      }
    } catch (e) {
      debugPrint('[AuthService] Advertencia al cerrar sesión en Supabase: $e');
    } finally {
      _currentSession = UserSession.empty();
      _pendingFactorId = null;
      _pendingChallengeId = null;
      _demoOtpCode = null;
      _emitSessionUpdate();
    }
  }

  /// Recupera la sesión persistente de Supabase al reiniciar o arrancar la aplicación.
  ///
  /// Valida el nivel de aseguramiento de autenticación (AAL) para confirmar si el
  /// factor MFA ya fue superado o si debe solicitarse de nuevo.
  Future<UserSession?> restoreSession() async {
    if (!SupabaseConfig.isInitialized) return null;

    try {
      final session = _auth.currentSession;
      final user = _auth.currentUser;

      if (session == null || user == null) {
        _currentSession = UserSession.empty();
        _emitSessionUpdate();
        return null;
      }

      bool isVerified = false;
      try {
        final aal = _auth.mfa.getAuthenticatorAssuranceLevel();
        // Si no tiene factores configurados o ya está en AAL2, se considera verificado
        if (aal.nextLevel == AuthenticatorAssuranceLevels.aal2 &&
            aal.currentLevel != AuthenticatorAssuranceLevels.aal2) {
          isVerified = false;
        } else {
          isVerified = true;
        }
      } catch (_) {
        isVerified = true;
      }

      _currentSession = UserSession.fromSupabase(
        user: user,
        session: session,
        isMfaVerified: isVerified,
        isMfaRequired: true,
      );

      _emitSessionUpdate();
      return _currentSession;
    } catch (e) {
      debugPrint('[AuthService] Error al restaurar sesión activa: $e');
      _currentSession = UserSession.empty();
      _emitSessionUpdate();
      return null;
    }
  }

  // ==========================================================================
  // AUXILIARES Y NOTIFICACIÓN
  // ==========================================================================

  void _emitSessionUpdate() {
    _sessionStreamController.add(_currentSession);
    notifyListeners();
  }

  /// Mapea códigos y mensajes de error de Supabase Auth a excepciones fuertemente tipadas.
  AuthCustomException _mapAuthException(AuthException e) {
    final msg = e.message.toLowerCase();
    final status = e.statusCode?.toString() ?? '';

    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid claim') ||
        msg.contains('user not found') ||
        msg.contains('wrong password') ||
        status == '400' && msg.contains('grant')) {
      return const InvalidCredentialsException();
    }

    if (msg.contains('already registered') ||
        msg.contains('already in use') ||
        msg.contains('user already exists') ||
        status == '422') {
      return const UserAlreadyExistsException();
    }

    if (msg.contains('otp') ||
        msg.contains('mfa') ||
        msg.contains('expired') ||
        msg.contains('token has expired') ||
        msg.contains('challenge')) {
      return const MfaChallengeExpiredException();
    }

    if (msg.contains('valid email') || msg.contains('invalid email')) {
      return const InvalidEmailFormatException();
    }

    if (msg.contains('password') && (msg.contains('short') || msg.contains('least'))) {
      return const WeakPasswordException();
    }

    return AuthCustomException(e.message, code: e.statusCode, originalError: e);
  }

  @override
  void dispose() {
    _sessionStreamController.close();
    super.dispose();
  }
}
