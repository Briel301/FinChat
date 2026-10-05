import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/ui_showcase/views/showcase_home_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FinChatApp());
}

/// Aplicación principal FinChat (FlutterMSG).
class FinChatApp extends StatelessWidget {
  const FinChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinChat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const ShowcaseHomeView(),
    );
  }
}
