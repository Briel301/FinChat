import 'package:flutter/material.dart';
import '../../media/services/media_service.dart';
import '../../chat/services/chat_service.dart';
import '../../chat/models/chat_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/optimization_utils.dart';

/// Vista interactiva para probar la grabación de notas de voz con tope estricto de 1 minuto (60s)
/// y optimización de bitrate para Supabase Storage.
class MediaRecorderView extends StatefulWidget {
  const MediaRecorderView({super.key});

  @override
  State<MediaRecorderView> createState() => _MediaRecorderViewState();
}

class _MediaRecorderViewState extends State<MediaRecorderView> {
  final _mediaService = MediaService();
  final _chatService = ChatService();
  String? _lastRecordedInfo;
  int? _lastDuration;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _mediaService,
      builder: (context, _) {
        final isRecording = _mediaService.isRecording;
        final seconds = _mediaService.recordDurationSeconds;
        final progress = (seconds / 60.0).clamp(0.0, 1.0);
        final remainingSeconds = 60 - seconds;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Grabador de Voz (Máx 1 Min)'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Banner de Requerimiento MoSCoW
                Card(
                  color: Colors.purple.shade50,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.mic_none, color: Colors.purple),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Must Have (10 pts): Envío y recepción de notas de audio de MÁXIMO 1 MINUTO (60s). Almacenamiento optimizado AAC mono 32 kbps en Supabase.',
                            style: TextStyle(fontSize: 13, color: Colors.purple.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // Cronómetro Central
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 190,
                        height: 190,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            remainingSeconds <= 10 ? Colors.red : AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isRecording ? Icons.mic : Icons.mic_none,
                            size: 48,
                            color: isRecording ? Colors.red : AppTheme.primaryColor,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            OptimizationUtils.formatDuration(seconds),
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                          ),
                          Text(
                            isRecording ? 'Restante: ${remainingSeconds}s' : 'Límite: 01:00',
                            style: TextStyle(
                              fontSize: 12,
                              color: remainingSeconds <= 10 ? Colors.red : AppTheme.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // Barra de progreso lineal
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    remainingSeconds <= 10 ? Colors.red : AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 30),

                // Botones de Acción
                if (!isRecording) ...[
                  ElevatedButton.icon(
                    onPressed: () => _mediaService.startVoiceRecording(),
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text('Iniciar Grabación de Audio'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _mediaService.cancelVoiceRecording(),
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          label: const Text('Descartar', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final attachment = await _mediaService.stopVoiceRecording();
                            setState(() {
                              _lastDuration = attachment.durationSeconds;
                              _lastRecordedInfo = 
                                  'Nota de ${_lastDuration}s procesada. Peso original: ${OptimizationUtils.formatBytes(attachment.originalSizeBytes)} -> Optimizado: ${OptimizationUtils.formatBytes(attachment.compressedSizeBytes)} (${attachment.savingsPercent.toStringAsFixed(1)}% de ahorro).';
                            });

                            // Envía directamente al chat
                            await _chatService.sendMessage(
                              text: '🎤 Nota de voz (${_lastDuration}s)',
                              type: MessageType.audio,
                              mediaUrl: attachment.remoteStorageUrl,
                              durationSeconds: _lastDuration,
                              fileSizeBytes: attachment.compressedSizeBytes,
                            );
                          },
                          icon: const Icon(Icons.send),
                          label: const Text('Finalizar y Enviar'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                ],

                // Tarjeta de Reporte de Optimización Supabase
                if (_lastRecordedInfo != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.savings_outlined, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Ahorro en Supabase Storage (Zero UI Jank)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(_lastRecordedInfo!, style: TextStyle(color: Colors.green.shade900, fontSize: 13)),
                        const SizedBox(height: 12),
                        const Text(
                          'El mensaje se envió exitosamente a la sala de chat.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
