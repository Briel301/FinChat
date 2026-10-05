import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../../../core/network/connectivity_service.dart';

/// Servicio de chat en tiempo real con soporte Offline-First y caché local.
class ChatService extends ChangeNotifier {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal() {
    _initDefaultMessages();
  }

  final List<ChatMessage> _messages = [];
  bool _isRecipientTyping = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isRecipientTyping => _isRecipientTyping;

  /// Cantidad de mensajes pendientes de sincronización por estar offline.
  int get pendingSyncCount => _messages.where((m) => !m.isSynced).length;

  void _initDefaultMessages() {
    final now = DateTime.now();
    _messages.addAll([
      ChatMessage(
        id: 'msg_001',
        chatId: 'chat_default',
        senderId: 'usr_001',
        senderUsername: 'usuario1',
        text: '¡Hola! Bienvenido a FinChat. ¿Pudiste revisar los requerimientos?',
        type: MessageType.text,
        status: MessageDeliveryStatus.read,
        timestamp: now.subtract(const Duration(minutes: 15)),
        isFromMe: false,
        isSynced: true,
      ),
      ChatMessage(
        id: 'msg_002',
        chatId: 'chat_default',
        senderId: 'usr_me',
        senderUsername: 'yo',
        text: '¡Sí! Ya configuramos la arquitectura modular con Supabase y modo offline.',
        type: MessageType.text,
        status: MessageDeliveryStatus.read,
        timestamp: now.subtract(const Duration(minutes: 10)),
        isFromMe: true,
        isSynced: true,
      ),
    ]);
  }

  /// Envía un mensaje respetando el estado de conectividad.
  Future<void> sendMessage({
    required String text,
    MessageType type = MessageType.text,
    String? mediaUrl,
    int? fileSizeBytes,
    int? durationSeconds,
  }) async {
    final isOnline = ConnectivityService().isOnline;
    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}';

    final newMessage = ChatMessage(
      id: messageId,
      chatId: 'chat_default',
      senderId: 'usr_me',
      senderUsername: 'yo',
      text: text,
      type: type,
      status: isOnline ? MessageDeliveryStatus.delivered : MessageDeliveryStatus.pending,
      timestamp: DateTime.now(),
      isFromMe: true,
      isSynced: isOnline,
      mediaUrl: mediaUrl,
      fileSizeBytes: fileSizeBytes,
      durationSeconds: durationSeconds,
    );

    _messages.add(newMessage);
    notifyListeners();

    // Si estamos online, simulamos respuesta automática y doble check azul tras 1.5s
    if (isOnline) {
      _simulateRecipientInteraction(newMessage.id);
    }
  }

  /// Sincroniza los mensajes acumulados en cola offline cuando se recupera internet.
  Future<int> syncPendingMessages() async {
    int syncedCount = 0;
    for (int i = 0; i < _messages.length; i++) {
      if (!_messages[i].isSynced) {
        _messages[i] = _messages[i].copyWith(
          isSynced: true,
          status: MessageDeliveryStatus.delivered,
        );
        syncedCount++;
      }
    }
    if (syncedCount > 0) {
      notifyListeners();
    }
    return syncedCount;
  }

  /// Simula la interacción del otro usuario: 'escribiendo...', lectura (doble check) y respuesta.
  void _simulateRecipientInteraction(String sentMessageId) {
    Timer(const Duration(milliseconds: 900), () {
      // Marcar como leído (doble check azul)
      final index = _messages.indexWhere((m) => m.id == sentMessageId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(status: MessageDeliveryStatus.read);
        _isRecipientTyping = true;
        notifyListeners();
      }

      // Responder tras simular escritura
      Timer(const Duration(milliseconds: 2000), () {
        _isRecipientTyping = false;
        _messages.add(ChatMessage(
          id: 'msg_reply_${DateTime.now().millisecondsSinceEpoch}',
          chatId: 'chat_default',
          senderId: 'usr_001',
          senderUsername: 'usuario1',
          text: 'Recibido correctamente. Funciona muy fluido.',
          type: MessageType.text,
          status: MessageDeliveryStatus.read,
          timestamp: DateTime.now(),
          isFromMe: false,
          isSynced: true,
        ));
        notifyListeners();
      });
    });
  }

  /// Alterna manualmente el estado del indicador 'escribiendo...' para pruebas UI.
  void setRecipientTyping(bool typing) {
    _isRecipientTyping = typing;
    notifyListeners();
  }
}
