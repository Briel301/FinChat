import 'dart:async';
import 'package:flutter/foundation.dart';

/// Servicio centralizado de conectividad para coordinar el modo Offline (Should Have: 7 pts).
/// Permite alternar entre estado de red real o simular desconexión en pruebas.
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  bool _isOnline = true;
  bool _isSimulatedOffline = false;

  bool get isOnline => !_isSimulatedOffline && _isOnline;
  bool get isSimulatedOffline => _isSimulatedOffline;

  /// Cambia el estado de red simulado para validar el modo Offline-First.
  void toggleOfflineSimulation(bool simulateOffline) {
    _isSimulatedOffline = simulateOffline;
    notifyListeners();
  }

  /// Actualiza el estado real de red.
  void setOnlineStatus(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      notifyListeners();
    }
  }
}
