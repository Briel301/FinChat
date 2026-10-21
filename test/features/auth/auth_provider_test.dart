import 'package:flutter_test/flutter_test.dart';
import 'package:finchat/features/auth/providers/auth_provider.dart';

void main() {
  group('AuthProvider State Lifecycle Tests', () {
    late AuthProvider authProvider;

    setUp(() {
      authProvider = AuthProvider();
    });

    tearDown(() async {
      await authProvider.logout();
    });

    test('Estado inicial es unauthenticated y sin sesión', () {
      expect(authProvider.status, equals(AuthStatus.unauthenticated));
      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.errorMessage, isNull);
    });

    test('register transiciona a awaitingMfa tras solicitud exitosa', () async {
      final success = await authProvider.register(
        username: 'prov_user',
        email: 'prov@finchat.app',
        password: 'password123',
        fullName: 'Usuario Provider',
      );

      expect(success, isTrue);
      expect(authProvider.status, equals(AuthStatus.awaitingMfa));
      expect(authProvider.isAwaitingMfa, isTrue);
      expect(authProvider.isAuthenticated, isFalse, reason: 'Bloqueo estricto: requiere MFA');
    });

    test('register transiciona a error ante datos inválidos', () async {
      final success = await authProvider.register(
        username: 'ab', // muy corto
        email: 'invalido',
        password: '123',
      );

      expect(success, isFalse);
      expect(authProvider.status, equals(AuthStatus.error));
      expect(authProvider.errorMessage, isNotNull);
    });

    test('verifyMfa con código correcto transiciona a authenticated', () async {
      await authProvider.login(
        identifier: 'usuario1',
        password: 'password123',
      );
      expect(authProvider.isAwaitingMfa, isTrue);

      final verified = await authProvider.verifyMfa('123456');
      expect(verified, isTrue);
      expect(authProvider.status, equals(AuthStatus.authenticated));
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.session.isMfaVerified, isTrue);
    });

    test('verifyMfa con código erróneo mantiene awaitingMfa y reporta error', () async {
      await authProvider.login(
        identifier: 'usuario1',
        password: 'password123',
      );

      final verified = await authProvider.verifyMfa('999999');
      expect(verified, isFalse);
      expect(authProvider.status, equals(AuthStatus.awaitingMfa));
      expect(authProvider.errorMessage, contains('inválido'));
      expect(authProvider.isAuthenticated, isFalse);
    });

    test('logout resetea el estado a unauthenticated y limpia sesión', () async {
      await authProvider.login(
        identifier: 'usuario1',
        password: 'password123',
      );
      await authProvider.verifyMfa('123456');
      expect(authProvider.isAuthenticated, isTrue);

      await authProvider.logout();
      expect(authProvider.status, equals(AuthStatus.unauthenticated));
      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.session.userId, isEmpty);
    });
  });
}
