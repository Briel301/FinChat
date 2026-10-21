import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/connectivity_service.dart';

/// Banner animado global para comunicar el estado de conectividad de FinChat.
///
/// - Cuando [ConnectivityService.isOnline] es `false`, se despliega suavemente
///   mostrando una alerta ámbar: "Sin conexión a internet. Mostrando historial local."
/// - Al restablecerse la conexión (`isOnline == true`), cambia a un estado verde:
///   "Conexión restablecida. Sincronizando..." y se oculta automáticamente tras 2 segundos.
/// - Permite inyectar [ConnectivityService] para pruebas o utilizar el provisto
///   por [Provider] / Singleton.
class OfflineBannerWidget extends StatefulWidget {
  final ConnectivityService? connectivityService;
  final Duration autoDismissDuration;

  const OfflineBannerWidget({
    super.key,
    this.connectivityService,
    this.autoDismissDuration = const Duration(seconds: 2),
  });

  @override
  State<OfflineBannerWidget> createState() => _OfflineBannerWidgetState();
}

class _OfflineBannerWidgetState extends State<OfflineBannerWidget>
    with SingleTickerProviderStateMixin {
  late ConnectivityService _service;
  bool _wasOffline = false;
  bool _showReconnected = false;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _service = widget.connectivityService ?? ConnectivityService();
    _wasOffline = !_service.isOnline;
    _service.addListener(_handleConnectivityChange);
  }

  @override
  void didUpdateWidget(covariant OfflineBannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connectivityService != oldWidget.connectivityService) {
      oldWidget.connectivityService?.removeListener(_handleConnectivityChange);
      _service = widget.connectivityService ?? ConnectivityService();
      _service.addListener(_handleConnectivityChange);
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _service.removeListener(_handleConnectivityChange);
    super.dispose();
  }

  void _handleConnectivityChange() {
    if (!mounted) return;
    final isOnline = _service.isOnline;

    if (!isOnline) {
      // Pasó a modo desconectado
      _dismissTimer?.cancel();
      setState(() {
        _wasOffline = true;
        _showReconnected = false;
      });
    } else if (_wasOffline) {
      // Volvió la conexión tras haber estado offline
      _dismissTimer?.cancel();
      setState(() {
        _showReconnected = true;
      });

      _dismissTimer = Timer(widget.autoDismissDuration, () {
        if (mounted) {
          setState(() {
            _showReconnected = false;
            _wasOffline = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si la app está provista por Provider, preferir escucharla si no se inyectó una explícita
    ConnectivityService effectiveService = _service;
    try {
      final providedService = Provider.of<ConnectivityService>(context, listen: true);
      effectiveService = widget.connectivityService ?? providedService;
    } catch (_) {
      // Sin Provider en el árbol, usar la instancia del servicio
    }

    final isOffline = !effectiveService.isOnline;
    final isVisible = isOffline || _showReconnected;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColor = isOffline
        ? (isDark ? const Color(0xFF5D4037) : const Color(0xFFFFF3CD))
        : (isDark ? const Color(0xFF1B4332) : const Color(0xFFD1E7DD));

    final textColor = isOffline
        ? (isDark ? const Color(0xFFFFCC80) : const Color(0xFF856404))
        : (isDark ? const Color(0xFF74C69D) : const Color(0xFF0F5132));

    final iconColor = textColor;
    final iconData = isOffline ? Icons.wifi_off_rounded : Icons.cloud_done_rounded;
    final messageText = isOffline
        ? 'Sin conexión a internet. Mostrando historial local.'
        : 'Conexión restablecida. Sincronizando...';

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: isVisible
          ? Semantics(
              liveRegion: true,
              label: messageText,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  border: Border(
                    bottom: BorderSide(
                      color: isOffline
                          ? (isDark ? Colors.orange.shade900 : const Color(0xFFFFEEBA))
                          : (isDark ? Colors.green.shade900 : const Color(0xFFBADBCC)),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      iconData,
                      size: 16,
                      color: iconColor,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        messageText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
