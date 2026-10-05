import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'auth_interactive_view.dart';
import 'directory_search_view.dart';
import 'chat_playground_view.dart';
import 'media_recorder_view.dart';
import 'offline_sync_view.dart';

/// Tablero principal interactivo para visualizar y validar todos los requerimientos
/// de la matriz MoSCoW y el documento Proyecto Final.
class ShowcaseHomeView extends StatelessWidget {
  const ShowcaseHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FinChat • Panel de Requerimientos'),
        elevation: 1,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // Banner de Cabecera con Arquitectura
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryColor, AppTheme.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.hub_outlined, color: Colors.white, size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Arquitectura Modular con Supabase BaaS',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Estructura optimizada: Compresión WebP en background (Isolates), audio AAC mono máx 60s, índices B-Tree y caché local para modo offline.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.energy_savings_leaf, color: Colors.greenAccent, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Ahorro estimado en Supabase Storage: > 80%',
                        style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Vistas Provisionales de Prueba (MoSCoW)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
          ),
          const SizedBox(height: 12),

          // 1. Autenticación MFA
          _buildFeatureCard(
            context: context,
            title: 'Autenticación & MFA',
            badgeText: 'Must Have • 10 pts',
            badgeColor: Colors.blue,
            icon: Icons.security,
            description: 'Registro e inicio de sesión sin SIM ni número telefónico. Verificación de doble factor (MFA) con código temporal de 6 dígitos.',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthInteractiveView())),
          ),

          // 2. Búsqueda Exacta
          _buildFeatureCard(
            context: context,
            title: 'Búsqueda Exacta de Usuario',
            badgeText: 'Must Have • 10 pts',
            badgeColor: Colors.amber.shade800,
            icon: Icons.person_search,
            description: 'Directorio de usuarios con filtro estricto por coincidencia exacta de "Nombre de Usuario" mediante índice PostgreSQL.',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DirectorySearchView())),
          ),

          // 3. Chat 1 a 1 en Tiempo Real
          _buildFeatureCard(
            context: context,
            title: 'Chat 1 a 1 en Tiempo Real',
            badgeText: 'Must Have • 10 pts',
            badgeColor: Colors.green,
            icon: Icons.chat,
            description: 'Envío y recepción de mensajes instantáneos, indicador "escribiendo...", confirmación de lectura con doble check azul e historial.',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatPlaygroundView())),
          ),

          // 4. Multimedia y Notas de Voz (1 min)
          _buildFeatureCard(
            context: context,
            title: 'Grabador de Voz (Máx 1 Min) & Medios',
            badgeText: 'Must Have • 30 pts',
            badgeColor: Colors.purple,
            icon: Icons.mic,
            description: 'Grabación de audio con límite forzado de 60 segundos, compresión AAC mono, envío de videos y fotos de cámara optimizadas.',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaRecorderView())),
          ),

          // 5. Modo Offline y Notificaciones Push
          _buildFeatureCard(
            context: context,
            title: 'Modo Offline & Push Notifications',
            badgeText: 'Should Have • 15 pts',
            badgeColor: Colors.teal,
            icon: Icons.offline_bolt,
            description: 'Lectura de mensajes sin conexión a internet desde caché local y simulador de notificaciones push en segundo plano.',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineSyncView())),
          ),
          const SizedBox(height: 20),

          // Resumen de Cumplimiento MoSCoW
          Card(
            elevation: 0,
            color: Colors.grey.shade100,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Matriz de Cobertura de Requerimientos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  _buildCheckItem('Autenticación MFA (Must Have 10 pts)', true),
                  _buildCheckItem('Búsqueda exacta por username (Must Have 10 pts)', true),
                  _buildCheckItem('Mensajes de texto 1 a 1 en tiempo real (Must Have 10 pts)', true),
                  _buildCheckItem('Envío/Recepción de fotos (Must Have 10 pts)', true),
                  _buildCheckItem('Envío/Recepción de videos (Must Have 10 pts)', true),
                  _buildCheckItem('Notas de audio de máx 1 min (Must Have 10 pts)', true),
                  _buildCheckItem('BaaS en la nube con Supabase (Must Have 10 pts)', true),
                  _buildCheckItem('Arquitectura Offline sin internet (Should Have 7 pts)', true),
                  _buildCheckItem('Notificaciones Push en segundo plano (Should Have 8 pts)', true),
                  _buildCheckItem('Indicador escribiendo y doble check azul (Could Have 6 pts)', true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String label, bool checked) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(checked ? Icons.check_circle : Icons.radio_button_unchecked, 
              color: checked ? AppTheme.primaryColor : Colors.grey, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required BuildContext context,
    required String title,
    required String badgeText,
    required Color badgeColor,
    required IconData icon,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: badgeColor.withOpacity(0.12),
                    radius: 20,
                    child: Icon(icon, color: badgeColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.3),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Abrir Vista Provisional',
                    style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 14, color: badgeColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
