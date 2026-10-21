import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/connectivity_service.dart';
import 'core/supabase/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'features/chat/views/real_chat_screen.dart';

void main() async {
  // Asegura enlace con el motor de Flutter antes de llamadas asíncronas
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialización de servicios de infraestructura
  await SupabaseConfig.initialize();
  await ConnectivityService().initialize();

  runApp(const FinChatApp());
}

/// Aplicación principal FinChat (FlutterMSG).
class FinChatApp extends StatelessWidget {
  const FinChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ConnectivityService()),
      ],
      child: MaterialApp(
        title: 'FinChat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const RealChatScreen(),
      ),
    );
  }
}
