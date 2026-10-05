import 'dart:async';
import 'package:flutter/foundation.dart';

/// Servicio de gestión y simulación de notificaciones push.
class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  String? _lastNotificationTitle;
  String? _lastNotificationBody;
  DateTime? _lastNotificationReceivedAt;

  String? get lastNotificationTitle => _lastNotificationTitle;
  String? get lastNotificationBody => _lastNotificationBody;
  DateTime? get lastNotificationReceivedAt => _lastNotificationReceivedAt;

  /// Simula la recepción de una notificación push como si la app estuviera en segundo plano.
  Future<void> simulateIncomingPush({
    required String senderUsername,
    required String messageText,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _lastNotificationTitle = 'Mensaje nuevo de @$senderUsername';
    _lastNotificationBody = messageText;
    _lastNotificationReceivedAt = DateTime.now();
    notifyListeners();
  }

  /// Limpia la última notificación leída.
  void clearNotification() {
    _lastNotificationTitle = null;
    _lastNotificationBody = null;
    notifyListeners();
  }
}
