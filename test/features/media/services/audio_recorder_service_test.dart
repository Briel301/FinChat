import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:finchat/features/media/services/audio_recorder_service.dart';

class FakeAudioRecorder extends AudioRecorder {
  bool hasPermissionResult = true;
  bool isStarted = false;
  bool isStopped = false;
  bool isCancelled = false;
  String? recordedPath;
  RecordConfig? lastConfig;

  @override
  Future<bool> hasPermission() async => hasPermissionResult;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    isStarted = true;
    lastConfig = config;
    recordedPath = path;
  }

  @override
  Future<String?> stop() async {
    isStopped = true;
    return recordedPath ?? '/tmp/simulated_voice_note.m4a';
  }

  @override
  Future<void> cancel() async {
    isCancelled = true;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAudioRecorder fakeRecorder;
  late AudioRecorderService recorderService;

  setUp(() {
    fakeRecorder = FakeAudioRecorder();
    recorderService = AudioRecorderService.custom(recorder: fakeRecorder);
  });

  tearDown(() async {
    await recorderService.dispose();
  });

  group('AudioRecorderService - Inicialización y Códec AAC-LC', () {
    test('verifica permisos de micrófono correctamente', () async {
      fakeRecorder.hasPermissionResult = true;
      expect(await recorderService.hasPermission(), isTrue);

      fakeRecorder.hasPermissionResult = false;
      expect(await recorderService.hasPermission(), isFalse);
    });

    test('configura la grabación con códec AAC-LC, 44100 Hz y 32 kbps (peso < 250 KB/min)', () async {
      await recorderService.startRecording(customPath: '/tmp/test_voice.m4a');

      expect(recorderService.isRecording, isTrue);
      expect(fakeRecorder.isStarted, isTrue);
      expect(fakeRecorder.recordedPath, '/tmp/test_voice.m4a');

      final config = fakeRecorder.lastConfig;
      expect(config, isNotNull);
      expect(config!.encoder, AudioEncoder.aacLc);
      expect(config.bitRate, AudioRecorderService.voiceBitRate); // 32,000 bps
      expect(config.sampleRate, AudioRecorderService.voiceSampleRate); // 44,100 Hz
      expect(config.numChannels, 1); // Canal Mono optimizado para voz humana

      // Cálculo matemático del peso máximo por minuto:
      // (32000 bits/s * 60 s) / 8 bits/byte = 240,000 bytes = ~234.37 KB (< 250 KB)
      final bytesPerMinute = (config.bitRate * 60) ~/ 8;
      expect(bytesPerMinute, lessThan(250 * 1024));
    });
  });

  group('AudioRecorderService - Temporizador y Regla Inflexible de 60 Segundos', () {
    test('emite segundos transcurridos mediante stream reactivo onSecondsElapsed', () async {
      final elapsedList = <int>[];
      final subscription = recorderService.onSecondsElapsed.listen((s) {
        elapsedList.add(s);
      });

      await recorderService.startRecording();
      await pumpEventQueue();

      expect(elapsedList, contains(0));

      await subscription.cancel();
      await recorderService.stopRecording();
    });

    test('corte forzado automático e instantáneo exactamente al alcanzar 60 segundos', () async {
      await recorderService.startRecording(customPath: '/tmp/corte_estricto_60s.m4a');
      expect(recorderService.isRecording, isTrue);

      bool maxLimitTriggered = false;
      final sub = recorderService.onMaxLimitReached.listen((_) {
        maxLimitTriggered = true;
      });

      // Simular que el temporizador llega a 60s
      await recorderService.handleTimerTickForTesting(60);
      await pumpEventQueue();

      // Debe activarse la notificación de límite alcanzado
      expect(maxLimitTriggered, isTrue);

      // La grabación debe quedar detenida inmediatamente
      expect(recorderService.isRecording, isFalse);
      expect(fakeRecorder.isStopped, isTrue);

      await sub.cancel();
    });

    test('detiene la grabación y retorna la ruta del archivo generado', () async {
      await recorderService.startRecording(customPath: '/tmp/nota_60s.m4a');
      expect(recorderService.isRecording, isTrue);

      final resultPath = await recorderService.stopRecording();

      expect(recorderService.isRecording, isFalse);
      expect(fakeRecorder.isStopped, isTrue);
      expect(resultPath, '/tmp/nota_60s.m4a');
    });

    test('cancelRecording descarta la sesión y limpia el estado', () async {
      await recorderService.startRecording();
      expect(recorderService.isRecording, isTrue);

      await recorderService.cancelRecording();

      expect(recorderService.isRecording, isFalse);
      expect(fakeRecorder.isCancelled, isTrue);
      expect(recorderService.currentRecordingPath, isNull);
    });

    test('constante estricta maxRecordingDurationSeconds es exactamente 60', () {
      expect(AudioRecorderService.maxRecordingDurationSeconds, 60);
    });
  });
}
