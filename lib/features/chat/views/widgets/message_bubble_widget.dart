import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/optimization_utils.dart';
import '../../models/chat_message.dart';

/// Widget ergonómico de burbuja de mensaje estilo WhatsApp / Material 3.
/// Soporta mensajes propios (alineados a la derecha, verde tenue) y recibidos (a la izquierda),
/// texto multilínea, salto de línea dinámico y marcas de tiempo con indicadores de entrega.
class MessageBubbleWidget extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final VoidCallback? onRetry;

  const MessageBubbleWidget({
    super.key,
    required this.message,
    required this.isMine,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final chatColors = context.chatColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Configuración de paleta según remitente
    final bubbleColor = isMine ? chatColors.outgoingBubble : chatColors.incomingBubble;
    final textColor = isMine ? chatColors.outgoingText : chatColors.incomingText;
    final metaColor = isMine ? chatColors.outgoingMeta : chatColors.incomingMeta;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isMine ? 14 : 2),
                bottomRight: Radius.circular(isMine ? 2 : 14),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black26 : Colors.black12,
                  blurRadius: 1.5,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 10, top: 7, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Contenido de texto con soporte multilínea
                  Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 15.5,
                      color: textColor,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 3),

                  // Fila inferior de Metadatos: Hora y Check de entrega
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Espaciador flexible para empujar la hora a la esquina derecha
                      const SizedBox(width: 8),
                      Text(
                        OptimizationUtils.formatTime(message.createdAt.toLocal()),
                        style: TextStyle(
                          fontSize: 11,
                          color: metaColor,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 4),
                        _buildDeliveryReceipt(chatColors),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Construye el indicador visual de estado de entrega (reloj, check simple, doble check o error).
  Widget _buildDeliveryReceipt(ChatColors chatColors) {
    if (message.status == MessageStatus.failed) {
      return InkWell(
        onTap: onRetry,
        child: const Tooltip(
          message: 'Error de envío. Toca para reintentar.',
          child: Icon(
            Icons.error_outline_rounded,
            size: 15,
            color: AppColors.errorLight,
          ),
        ),
      );
    }

    if (!message.isSynced || message.status == MessageStatus.sending) {
      return Tooltip(
        message: 'Pendiente de sincronizar (Offline)',
        child: Icon(
          Icons.access_time_rounded,
          size: 13,
          color: chatColors.outgoingMeta,
        ),
      );
    }

    switch (message.status) {
      case MessageStatus.sent:
        return Tooltip(
          message: 'Enviado',
          child: Icon(
            Icons.check_rounded,
            size: 15,
            color: chatColors.sentReceipt,
          ),
        );
      case MessageStatus.delivered:
        return Tooltip(
          message: 'Entregado',
          child: Icon(
            Icons.done_all_rounded,
            size: 16,
            color: chatColors.sentReceipt,
          ),
        );
      case MessageStatus.read:
        return Tooltip(
          message: 'Leído',
          child: Icon(
            Icons.done_all_rounded,
            size: 16,
            color: chatColors.readReceipt,
          ),
        );
      case MessageStatus.sending:
      case MessageStatus.failed:
        return const SizedBox.shrink();
    }
  }
}
