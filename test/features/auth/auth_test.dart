import 'package:flutter_test/flutter_test.dart';
import 'package:finchat/features/auth/models/user_session.dart';
import 'package:finchat/features/auth/services/auth_service.dart';

void main() {
  group('UserSession Entity Tests', () {
    test('UserSession inicializa con valores requeridos e inmutabilidad', () {
      final now = DateTime.now();
      final session = UserSession(
        userId: 'usr_abc_123',
        email: 'test@finchat.app',
        username: 'fin_tester',
        createdAt: now,
      );

      expect(session.userId, equals('usr_abc_123'));
      expect(session.email, equals('test@finchat.app'));
      expect(session.username, equals('fin_tester'));
      expect(session.isMfaVerified, isFalse);
      expect(session.isAuthenticated, isFalse, reason: 'Bloqueo estricto: sin MFA no está autenticado');
      expect(session.createdAt, equals(now));
    });

    test('UserSession isAuthenticated requiere estrictamente isMfaVerified en true', () {
      final sessionUnverified = UserSession(
        userId: 'usr_valid_id',
        email: 'user@finchat.app',
        username: 'user_fin',
        isMfaVerified: false,
      );
      expect(sessionUnverified.isAuthenticated, isFalse);

      final sessionVerified = sessionUnverified.copyWith(isMfaVerified: true);
      expect(sessionVerified.isAuthenticated, isTrue);

      final sessionEmptyId = sessionVerified.copyWith(userId: '');
      expect(sessionEmptyId.isAuthenticated, isFalse);
    });

    test('UserSession serialización toMap y fromMap preserva todos los campos', () {
      final original = UserSession(
        userId: 'uuid_0099',
        email: 'dev@finchat.app',
        username: 'developer99',
        fullName: 'Dev Senior',
        avatarUrl: 'https://storage.supabase.co/avatar.png',
        accessToken: 'jwt_mock_token_xyz',
        isMfaVerified: true,
        isMfaRequired: true,
        createdAt: DateTime.parse('2026-10-10T12:00:00.000Z'),
      );

      final map = original.toMap();
      final reconstructed = UserSession.fromMap(map);

      expect(reconstructed.userId, equals(original.userId));
      expect(reconstructed.email, equals(original.email));
      expect(reconstructed.username, equals(original.username));
      expect(reconstructed.fullName, equals(original.fullName));
      expect(reconstructed.avatarUrl, equals(original.avatarUrl));
      expect(reconstructed.accessToken, equals(original.accessToken));
      expect(reconstructed.isMfaVerified, isTrue);
      expect(reconstructed.createdAt.toIso8601String(), equals(original.createdAt.toIso8601String()));
    });

    test('UserSession.empty() retorna instancia reseteada', () {
      final empty = UserSession.empty();
      expect(empty.userId, isEmpty);
      expect(empty.email, isEmpty);
      expect(empty.username, isEmpty);
      expect(empty.isMfaVerified, isFalse);
      expect(empty.isAuthenticated, isFalse);
    });
  });

  group('AuthService Core Logic & MFA Verification Tests', () {
    late AuthService authService;

    setUp(() {
      authService = AuthService();
    });

    tearDown(() async {
      await authService.signOut();
    });

    test('signUp valida formato de email incorrecto', () async {
      expect(
        () => authService.signUp(
          email: 'email_invalido_sin_arroba',
          password: 'password123',
          username: 'usuario_valido',
        ),
        throwsA(isA<InvalidEmailFormatException>()),
      );
    });

    test('signUp valida formato de username con caracteres inválidos o muy corto', () async {
      expect(
        () => authService.signUp(
          email: 'test@finchat.app',
          password: 'password123',
          username: 'a!', // Carácter especial no permitido y menor a 3 caracteres
        ),
        throwsA(isA<AuthCustomException>()),
      );
    });

    test('signUp valida longitud mínima de contraseña', () async {
      expect(
        () => authService.signUp(
          email: 'test@finchat.app',
          password: '123', // Menor a 6 caracteres
          username: 'usuario_valido',
        ),
        throwsA(isA<WeakPasswordException>()),
      );
    });

    test('Flujo de registro y desafío MFA interactivo', () async {
      // 1. Registro inicial
      final session = await authService.signUp(
        email: 'nuevo@finchat.app',
        password: 'securePassword123',
        username: 'nuevo_usuario',
        fullName: 'Nuevo Usuario FinChat',
      );

      // Bloqueo estricto: Se genera sesión pero NO está autenticado hasta superar MFA
      expect(session.userId, isNotEmpty);
      expect(session.username, equals('nuevo_usuario'));
      expect(session.isMfaVerified, isFalse);
      expect(authService.isLoggedIn, isFalse);

      // 2. Intento con código MFA erróneo
      final failResult = await authService.verifyMfaCode('999999');
      expect(failResult, isFalse);
      expect(authService.isLoggedIn, isFalse);

      // 3. Confirmación con código MFA exitoso (6 dígitos)
      final successResult = await authService.verifyMfaCode('123456');
      expect(successResult, isTrue);
      expect(authService.isLoggedIn, isTrue);
      expect(authService.currentSession.isMfaVerified, isTrue);

      // 4. Cierre de sesión
      await authService.signOut();
      expect(authService.isLoggedIn, isFalse);
      expect(authService.currentSession.userId, isEmpty);
    });

    test('Flujo de inicio de sesión signIn y confirmación MFA', () async {
      final session = await authService.signIn(
        identifier: 'usuario1',
        password: 'password123',
      );

      expect(session.username, equals('usuario1'));
      expect(session.isMfaVerified, isFalse);
      expect(authService.isLoggedIn, isFalse);

      // Verificación MFA
      final ok = await authService.verifyMfaCode('123456');
      expect(ok, isTrue);
      expect(authService.isLoggedIn, isTrue);
    });
  });
}
