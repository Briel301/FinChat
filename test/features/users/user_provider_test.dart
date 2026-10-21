import 'package:flutter_test/flutter_test.dart';
import 'package:finchat/features/users/providers/user_provider.dart';

void main() {
  group('UserProvider Search & Profile Management Tests', () {
    late UserProvider userProvider;

    setUp(() {
      userProvider = UserProvider();
    });

    test('Estado inicial sin búsqueda y con usuarios demo disponibles', () {
      expect(userProvider.searchResult, isNull);
      expect(userProvider.hasSearched, isFalse);
      expect(userProvider.isSearching, isFalse);
      expect(userProvider.demoUsers, isNotEmpty);
    });

    test('searchUser encuentra usuario por coincidencia exacta y actualiza hasSearched', () async {
      final user = await userProvider.searchUser('usuario1');

      expect(user, isNotNull);
      expect(userProvider.searchResult, isNotNull);
      expect(userProvider.searchResult!.username, equals('usuario1'));
      expect(userProvider.hasSearched, isTrue);
      expect(userProvider.isSearching, isFalse);
    });

    test('searchUser retorna null ante coincidencia parcial o inexistente', () async {
      final user = await userProvider.searchUser('usuario'); // parcial

      expect(user, isNull);
      expect(userProvider.searchResult, isNull);
      expect(userProvider.hasSearched, isTrue);
      expect(userProvider.isSearching, isFalse);
    });

    test('clearSearch limpia el estado de la búsqueda', () async {
      await userProvider.searchUser('usuario1');
      expect(userProvider.hasSearched, isTrue);

      userProvider.clearSearch();
      expect(userProvider.hasSearched, isFalse);
      expect(userProvider.searchResult, isNull);
    });

    test('updateBio actualiza biografía y valida restricción de 160 caracteres', () async {
      final success = await userProvider.updateBio(
        'Desarrollador Flutter Senior',
        userId: 'usr_001',
      );
      expect(success, isTrue);

      final invalidSuccess = await userProvider.updateBio(
        'X' * 161, // supera 160
        userId: 'usr_001',
      );
      expect(invalidSuccess, isFalse);
      expect(userProvider.errorMessage, contains('160'));
    });

    test('updateFullName actualiza nombre completo', () async {
      final success = await userProvider.updateFullName(
        'Carlos Santana Actualizado',
        userId: 'usr_001',
      );
      expect(success, isTrue);
    });
  });
}
