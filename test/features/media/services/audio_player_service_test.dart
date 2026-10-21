import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finchat/features/media/services/audio_player_service.dart';

class FakeAudioPlayer extends AudioPlayer {
  Source? lastSource;
  PlayerState simulatedState = PlayerState.stopped;
  Duration simulatedDuration = Duration.zero;
  Duration simulatedPosition = Duration.zero;

  final _stateController = StreamController<PlayerState>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  @override
  Stream<PlayerState> get onPlayerStateChanged => _stateController.stream;

  @override
  Stream<Duration> get onDurationChanged => _durationController.stream;

  @override
  Stream<Duration> get onPositionChanged => _positionController.stream;

  @override
  Future<void> play(Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    lastSource = source;
    simulatedState = PlayerState.playing;
    _stateController.add(simulatedState);
  }

  @override
  Future<void> pause() async {
    simulatedState = PlayerState.paused;
    _stateController.add(simulatedState);
  }

  @override
  Future<void> resume() async {
    simulatedState = PlayerState.playing;
    _stateController.add(simulatedState);
  }

  @override
  Future<void> seek(Duration position) async {
    simulatedPosition = position;
    _positionController.add(position);
  }

  @override
  Future<void> stop() async {
    simulatedState = PlayerState.stopped;
    _stateController.add(simulatedState);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _durationController.close();
    await _positionController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async => 1,
    );
  });

  late FakeAudioPlayer fakePlayer;
  late AudioPlayerService playerService;

  setUp(() {
    fakePlayer = FakeAudioPlayer();
    playerService = AudioPlayerService.custom(player: fakePlayer);
  });

  tearDown(() async {
    await playerService.dispose();
  });

  group('AudioPlayerService - Reproducción Local y Supabase URLs', () {
    test('reproduce URL remota de Supabase envolviéndola en UrlSource', () async {
      const remoteUrl = 'https://supabase.co/storage/v1/object/public/chat_media/chat1/usr1/voice.m4a';

      await playerService.play(remoteUrl);

      expect(playerService.currentSource, remoteUrl);
      expect(fakePlayer.lastSource, isA<UrlSource>());
      expect((fakePlayer.lastSource as UrlSource).url, remoteUrl);
    });

    test('reproduce ruta local del dispositivo envolviéndola en DeviceFileSource', () async {
      const localPath = '/data/user/0/com.finchat/cache/voice_note_123.m4a';

      await playerService.play(localPath);

      expect(playerService.currentSource, localPath);
      expect(fakePlayer.lastSource, isA<DeviceFileSource>());
      expect((fakePlayer.lastSource as DeviceFileSource).path, localPath);
    });
  });

  group('AudioPlayerService - Controles de Reproducción y Estado', () {
    test('pausa y reanuda la reproducción actualizando el estado reactivo', () async {
      await playerService.play('https://example.com/audio.m4a');
      expect(playerService.isPlaying, isTrue);

      await playerService.pause();
      expect(playerService.state, PlayerState.paused);
      expect(playerService.isPlaying, isFalse);

      await playerService.resume();
      expect(playerService.state, PlayerState.playing);
      expect(playerService.isPlaying, isTrue);
    });

    test('seek desplaza la posición de reproducción', () async {
      await playerService.play('/tmp/audio.m4a');
      const targetPos = Duration(seconds: 24);

      await playerService.seek(targetPos);

      expect(fakePlayer.simulatedPosition, targetPos);
    });

    test('stop detiene la reproducción y resetea la posición', () async {
      await playerService.play('/tmp/audio.m4a');
      await playerService.stop();

      expect(playerService.state, PlayerState.stopped);
      expect(playerService.position, Duration.zero);
    });
  });
}
