import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/user_session.dart';
import '../services/auth_service.dart';

/// Estados posibles del ciclo de autenticación en FinChat.
enum AuthStatus {
  /// Sin sesión activa en el dispositivo.
  unauthenticated,

  /// Ejecutando llamada de red de registro o inicio de sesión.
  authenticating,

  /// Credenciales validadas; en espera estricta del código MFA de 6 dígitos.
  awaitingMfa,

  /// Usuario autenticado plenamente tras superar el segundo factor.
  authenticated,

  /// Ocurrió un error en la solicitud (red, credenciales, formato, etc.).
  error,
}

/// Proveedor de estado para la autenticación de FinChat con soporte estricto de MFA (Doble Factor).
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  AuthStatus _status = AuthStatus.unauthenticated;
  UserSession _session = UserSession.empty();
  String? _errorMessage;
  int _mfaResendSeconds = 0;
  Timer? _resendTimer;

  AuthProvider({AuthService? authService})
      : _authService = authService ?? AuthService() {
    _init();
  }

  /// Inicializa escuchando cambios de sesión y restaurando sesión previa.
  Future<void> _init() async {
    _session = _authService.currentSession;
    if (_session.isAuthenticated) {
      _status = AuthStatus.authenticated;
    } else if (_session.userId.isNotEmpty && !_session.isMfaVerified) {
      _status = AuthStatus.awaitingMfa;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();

    // Intentar recuperar sesión persistente de Supabase
    try {
      final restored = await _authService.restoreSession();
      if (restored != null) {
        _session = restored;
        _status = restored.isAuthenticated
            ? AuthStatus.authenticated
            : (restored.userId.isNotEmpty ? AuthStatus.awaitingMfa : AuthStatus.unauthenticated);
        notifyListeners();
      }
    } catch (_) {
      // Ignorar errores en arranque sin conexión
    }
  }

  // ==========================================================================
  // GETTERS DE ESTADO
  // ==========================================================================

  AuthStatus get status => _status;
  UserSession get session => _session;
  String? get errorMessage => _errorMessage;
  int get mfaResendSeconds => _mfaResendSeconds;
  bool get canResendMfa => _mfaResendSeconds == 0;

  bool get isLoading => _status == AuthStatus.authenticating;
  bool get isAwaitingMfa => _status == AuthStatus.awaitingMfa;
  bool get isAuthenticated => _status == AuthStatus.authenticated && _session.isAuthenticated;

  // ==========================================================================
  // 1. REGISTRO (SIN TELÉFONO NI SIM)
  // ==========================================================================

  /// Registra una nueva cuenta y bloquea el acceso en espera del código MFA.
  Future<bool> register({
    required String username,
    required String email,
    required String password,
    String? fullName,
  }) async {
    _setStatus(AuthStatus.authenticating);
    _clearError();

    try {
      final newSession = await _authService.signUp(
        email: email,
        password: password,
        username: username,
        fullName: fullName,
      );

      _session = newSession;
      _startResendCooldown();
      _setStatus(AuthStatus.awaitingMfa);
      return true;
    } on AuthCustomException catch (e) {
      _setError(e.message);
      return false;
    } catch (e) {
      _setError('Error al registrar usuario: $e');
      return false;
    }
  }

  // ==========================================================================
  // 2. INICIO DE SESIÓN
  // ==========================================================================

  /// Autentica con usuario/correo y contraseña, preparando el reto MFA.
  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    _setStatus(AuthStatus.authenticating);
    _clearError();

    try {
      final userSession = await _authService.signIn(
        identifier: identifier,
        password: password,
      );

      _session = userSession;
      _startResendCooldown();
      _setStatus(AuthStatus.awaitingMfa);
      return true;
    } on AuthCustomException catch (e) {
      _setError(e.message);
      return false;
    } catch (e) {
      _setError('Error al iniciar sesión: $e');
      return false;
    }
  }

  // ==========================================================================
  // 3. DESAFÍO Y VALIDACIÓN MFA (OTP DE 6 DÍGITOS)
  // ==========================================================================

  /// Valida el código de 6 dígitos con Supabase. Al superarlo, desbloquea la app.
  Future<bool> verifyMfa(String code) async {
    final cleanCode = code.trim();
    if (cleanCode.length != 6) {
      _setError('El código MFA debe tener exactamente 6 dígitos.');
      return false;
    }

    _setStatus(AuthStatus.authenticating);
    _clearError();

    try {
      final verified = await _authService.verifyMfaCode(cleanCode);
      if (verified) {
        _session = _authService.currentSession;
        _setStatus(AuthStatus.authenticated);
        return true;
      } else {
        _setError('Código MFA inválido o expirado. Ingresa los 6 dígitos correctos.');
        _setStatus(AuthStatus.awaitingMfa);
        return false;
      }
    } catch (e) {
      _setError('Fallo al validar código de verificación: $e');
      _setStatus(AuthStatus.awaitingMfa);
      return false;
    }
  }

  /// Reinicia el contador de reenvío de código MFA.
  void resendMfaCode() {
    if (!canResendMfa) return;
    _startResendCooldown();
    notifyListeners();
  }

  void _startResendCooldown() {
    _mfaResendSeconds = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_mfaResendSeconds <= 1) {
        _mfaResendSeconds = 0;
        timer.cancel();
      } else {
        _mfaResendSeconds--;
      }
      notifyListeners();
    });
  }

  // ==========================================================================
  // 4. CIERRE DE SESIÓN
  // ==========================================================================

  /// Cierra la sesión activa en el backend y limpia el estado local.
  Future<void> logout() async {
    _resendTimer?.cancel();
    _mfaResendSeconds = 0;
    await _authService.signOut();
    _session = UserSession.empty();
    _errorMessage = null;
    _setStatus(AuthStatus.unauthenticated);
  }

  // ==========================================================================
  // MANEJO DE ESTADO INTERNO
  // ==========================================================================

  void _setStatus(AuthStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  void _setError(String msg) {
    _errorMessage = msg;
    _status = AuthStatus.error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  /// Limpia manualmente el mensaje de error activo.
  void clearError() {
    _clearError();
    if (_status == AuthStatus.error) {
      _status = _session.userId.isNotEmpty && !_session.isMfaVerified
          ? AuthStatus.awaitingMfa
          : AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }
}
