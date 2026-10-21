import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finchat/core/network/connectivity_service.dart';
import 'package:finchat/features/chat/views/widgets/offline_banner_widget.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestableBanner({
    required ConnectivityService service,
    ThemeMode themeMode = ThemeMode.light,
    Duration autoDismissDuration = const Duration(seconds: 2),
  }) {
    return MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      home: Scaffold(
        body: OfflineBannerWidget(
          connectivityService: service,
          autoDismissDuration: autoDismissDuration,
        ),
      ),
    );
  }

  testWidgets('1. Cuando isOnline es true, el banner permanece colapsado sin texto', (tester) async {
    final connectivity = ConnectivityService();
    connectivity.toggleOfflineSimulation(false);

    await tester.pumpWidget(buildTestableBanner(service: connectivity));
    await tester.pumpAndSettle();

    expect(find.text('Sin conexión a internet. Mostrando historial local.'), findsNothing);
    expect(find.text('Conexión restablecida. Sincronizando...'), findsNothing);
    expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
  });

  testWidgets('2. Al pasar a offline, despliega banner ámbar con texto de aviso e icono wifi_off', (tester) async {
    final connectivity = ConnectivityService();
    connectivity.toggleOfflineSimulation(false);

    await tester.pumpWidget(buildTestableBanner(service: connectivity));
    await tester.pumpAndSettle();

    // Simular desconexión
    connectivity.toggleOfflineSimulation(true);
    await tester.pumpAndSettle();

    expect(find.text('Sin conexión a internet. Mostrando historial local.'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
  });

  testWidgets('3. Al reconectar tras estar offline, muestra banner verde y se oculta tras 2 segundos', (tester) async {
    final connectivity = ConnectivityService();
    connectivity.toggleOfflineSimulation(true); // Inicia offline

    await tester.pumpWidget(
      buildTestableBanner(
        service: connectivity,
        autoDismissDuration: const Duration(seconds: 2),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sin conexión a internet. Mostrando historial local.'), findsOneWidget);

    // Reconectar a internet
    connectivity.toggleOfflineSimulation(false);
    await tester.pump(); // Inicia animación y estado reconnected

    expect(find.text('Conexión restablecida. Sincronizando...'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);

    // Avanzar 1 segundo: aún visible
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Conexión restablecida. Sincronizando...'), findsOneWidget);

    // Avanzar más allá de los 2 segundos: se oculta automáticamente
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Conexión restablecida. Sincronizando...'), findsNothing);
    expect(find.text('Sin conexión a internet. Mostrando historial local.'), findsNothing);
  });

  testWidgets('4. Soporta Modo Oscuro (Dark Theme) con estilos legibles', (tester) async {
    final connectivity = ConnectivityService();
    connectivity.toggleOfflineSimulation(true);

    await tester.pumpWidget(
      buildTestableBanner(
        service: connectivity,
        themeMode: ThemeMode.dark,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sin conexión a internet. Mostrando historial local.'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
  });
}
