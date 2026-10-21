import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Servicio de reproducción de notas de voz y archivos de audio en FinChat.
///
/// Soporta reproducción fluida tanto desde rutas locales (`DeviceFileSource`)
/// como desde URLs públicas/firmadas de Supabase Storage (`UrlSource`).
class AudioPlayerService {
  final AudioPlayer _player;
  final bool _isCustomPlayer;

  String? _currentSource;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  PlayerState _state = PlayerState.stopped;

  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  AudioPlayerService()
      : _player = AudioPlayer(),
        _isCustomPlayer = false {
    _initSubscriptions();
  }

  @visibleForTesting
  AudioPlayerService.custom({AudioPlayer? player})
      : _player = player ?? AudioPlayer(),
        _isCustomPlayer = true {
    _initSubscriptions();
  }

  void _initSubscriptions() {
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      _state = state;
    });

    _durationSubscription = _player.onDurationChanged.listen((duration) {
      _duration = duration;
    });

    _positionSubscription = _player.onPositionChanged.listen((position) {
      _position = position;
    });
  }

  /// Estado actual del reproductor (stopped, playing, paused, completed).
  PlayerState get state => _state;

  /// Indica si el reproductor está actualmente en reproducción activa.
  bool get isPlaying => _state == PlayerState.playing;

  /// Duración total del audio cargado actualmente.
  Duration get duration => _duration;

  /// Posición actual de reproducción en el audio.
  Duration get position => _position;

  /// Origen o URL del audio actual.
  String? get currentSource => _currentSource;

  /// Stream reactivo de cambios de estado del reproductor.
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;

  /// Stream reactivo de la duración total del audio.
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;

  /// Stream reactivo del avance de la barra de reproducción (posición actual).
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;

  /// Stream reactivo cuando el audio finaliza completamente.
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  /// Reproduce un audio desde una URL remota de Supabase o una ruta local del dispositivo.
  Future<void> play(String sourceUrl) async {
    _currentSource = sourceUrl;

    Source source;
    if (sourceUrl.startsWith('http://') || sourceUrl.startsWith('https://')) {
      source = UrlSource(sourceUrl);
    } else {
      source = DeviceFileSource(sourceUrl);
    }

    try {
      await _player.play(source);
    } catch (e) {
      debugPrint('[AudioPlayerService] Error al reproducir audio: $e');
      if (_isCustomPlayer) rethrow;
    }
  }

  /// Pausa la reproducción activa del audio.
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('[AudioPlayerService] Error al pausar audio: $e');
    }
  }

  /// Reanuda la reproducción desde la última posición pausada.
  Future<void> resume() async {
    try {
      await _player.resume();
    } catch (e) {
      debugPrint('[AudioPlayerService] Error al reanudar audio: $e');
    }
  }

  /// Desplaza la reproducción a una posición específica (útil para sliders interactivos).
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
      debugPrint('[AudioPlayerService] Error al mover posición (seek): $e');
    }
  }

  /// Detiene la reproducción y reinicia la posición al inicio (00:00).
  Future<void> stop() async {
    try {
      await _player.stop();
      _position = Duration.zero;
    } catch (e) {
      debugPrint('[AudioPlayerService] Error al detener audio: $e');
    }
  }

  /// Libera todas las suscripciones e instancias nativas de AudioPlayer.
  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _positionSubscription?.cancel();
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
