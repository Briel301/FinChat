import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/connectivity_service.dart';
import 'core/supabase/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/chat/providers/chat_provider.dart';
import 'features/chat/services/chat_service.dart';
import 'features/ui_showcase/views/showcase_home_view.dart';
import 'features/users/providers/user_provider.dart';

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
        ChangeNotifierProvider.value(value: ChatService()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: MaterialApp(
        title: 'FinChat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const ShowcaseHomeView(),
      ),
    );
  }
}
