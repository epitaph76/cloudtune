import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../providers/local_music_provider.dart';
import '../services/audio_handler.dart';

class AudioPlayerProvider with ChangeNotifier {
  LocalMusicProvider _localMusicProvider;
  final MyAudioHandler _audioHandler;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  int _currentIndex = -1;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _duration = Duration.zero;
  ProcessingState _processingState = ProcessingState.idle;
  int _lastNotifiedPositionMs = 0;

  AudioPlayerProvider(this._localMusicProvider, this._audioHandler) {
    _setupStreams();
  }

  void updateLocalMusicProvider(LocalMusicProvider localMusicProvider) {
    _localMusicProvider = localMusicProvider;

    if (_currentIndex >= _localMusicProvider.selectedFiles.length) {
      _currentIndex = -1;
      _duration = Duration.zero;
      _position = Duration.zero;
      _bufferedPosition = Duration.zero;
    }
    notifyListeners();
  }

  List<File> get audioFiles => _localMusicProvider.selectedFiles;

  ProcessingState get processingState => _processingState;
  bool get playing => _playing;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition;
  Duration get duration => _duration;
  int get currentIndex => _currentIndex;
  bool isCurrentTrack(int index) => _currentIndex == index && _currentIndex != -1;
  bool isTrackPlaying(int index) => isCurrentTrack(index) && _playing;

  void _setupStreams() {
    _subscriptions.add(_audioHandler.playbackState.listen((state) {
      final nextPlaying = state.playing;
      final nextBuffered = state.bufferedPosition;
      final nextProcessingState = _mapProcessingState(state.processingState);
      final nextPosition = state.updatePosition;

      final changed = _playing != nextPlaying ||
          _bufferedPosition != nextBuffered ||
          _processingState != nextProcessingState;

      _playing = nextPlaying;
      _bufferedPosition = nextBuffered;
      _processingState = nextProcessingState;

      if (!_playing && nextPosition == Duration.zero) {
        _position = Duration.zero;
        _lastNotifiedPositionMs = 0;
      }

      if (changed) {
        notifyListeners();
      }
    }));

    _subscriptions.add(AudioService.position.listen((pos) {
      if (!_playing) return;

      // Throttle position UI updates to avoid excessive rebuilds.
      final posMs = pos.inMilliseconds;
      if ((posMs - _lastNotifiedPositionMs).abs() < 200) return;

      _position = pos;
      _lastNotifiedPositionMs = posMs;
      notifyListeners();
    }));

    _subscriptions.add(_audioHandler.mediaItem.listen((item) {
      if (item == null) return;
      final nextDuration = item.duration ?? Duration.zero;
      final durationChanged = _duration != nextDuration;
      _duration = nextDuration;
      _syncCurrentIndexByPath(item.id);
      if (durationChanged) {
        notifyListeners();
      }
    }));

    _subscriptions.add(_audioHandler.queue.listen((_) {
      final currentId = _audioHandler.mediaItem.value?.id;
      if (currentId != null) {
        final prevIndex = _currentIndex;
        _syncCurrentIndexByPath(currentId);
        if (prevIndex != _currentIndex) {
          notifyListeners();
        }
      }
    }));
  }

  void _syncCurrentIndexByPath(String path) {
    final idx =
        _localMusicProvider.selectedFiles.indexWhere((file) => file.path == path);
    if (idx != -1) {
      _currentIndex = idx;
    }
  }

  ProcessingState _mapProcessingState(AudioProcessingState state) {
    switch (state) {
      case AudioProcessingState.idle:
        return ProcessingState.idle;
      case AudioProcessingState.loading:
        return ProcessingState.loading;
      case AudioProcessingState.buffering:
        return ProcessingState.buffering;
      case AudioProcessingState.ready:
        return ProcessingState.ready;
      case AudioProcessingState.completed:
        return ProcessingState.completed;
      default:
        return ProcessingState.idle;
    }
  }

  Future<void> playAudioAt(int index) async {
    final files = _localMusicProvider.selectedFiles;
    if (index < 0 || index >= files.length) return;

    final items = files
        .map(
          (file) => MediaItem(
            id: file.path,
            album: '',
            title: p.basename(file.path),
          ),
        )
        .toList();

    await _audioHandler.setQueue(items, initialIndex: index);
    await _audioHandler.play();

    _currentIndex = index;
    notifyListeners();
  }

  Future<void> playPause() async {
    final isPlaying = _audioHandler.playbackState.value.playing;
    if (isPlaying) {
      await _audioHandler.pause();
    } else {
      await _audioHandler.play();
    }
  }

  Future<void> toggleTrackAt(int index) async {
    if (index < 0 || index >= _localMusicProvider.selectedFiles.length) return;

    if (isCurrentTrack(index)) {
      await playPause();
      return;
    }

    await playAudioAt(index);
  }

  Future<void> seek(Duration newPosition) async {
    await _audioHandler.seek(newPosition);
  }

  Future<void> skipToNext() async {
    await _audioHandler.skipToNext();
  }

  Future<void> skipToPrevious() async {
    await _audioHandler.skipToPrevious();
  }

  Future<void> stop() async {
    await _audioHandler.stop();
    _currentIndex = -1;
    _playing = false;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _duration = Duration.zero;
    _processingState = ProcessingState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }
}
