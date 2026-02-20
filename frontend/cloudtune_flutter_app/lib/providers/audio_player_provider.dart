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
  String? _currentTrackPath;
  List<String> _activeQueuePaths = <String>[];
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _duration = Duration.zero;
  ProcessingState _processingState = ProcessingState.idle;
  int _lastNotifiedPositionMs = 0;
  bool _shuffleEnabled = false;
  bool _repeatOneEnabled = false;
  double _volume = 0.7;

  AudioPlayerProvider(this._localMusicProvider, this._audioHandler) {
    _shuffleEnabled = _audioHandler.shuffleEnabled;
    _repeatOneEnabled = _audioHandler.loopMode == LoopMode.one;
    _volume = _audioHandler.volume;
    _setupStreams();
  }

  void updateLocalMusicProvider(LocalMusicProvider localMusicProvider) {
    _localMusicProvider = localMusicProvider;
    final existingPaths = _localMusicProvider.selectedFiles
        .map((file) => file.path)
        .toSet();

    _activeQueuePaths = _activeQueuePaths
        .where(existingPaths.contains)
        .toList();

    if (_currentTrackPath != null && !existingPaths.contains(_currentTrackPath)) {
      _currentTrackPath = null;
      _currentIndex = -1;
      _duration = Duration.zero;
      _position = Duration.zero;
      _bufferedPosition = Duration.zero;
    }

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
  bool get shuffleEnabled => _shuffleEnabled;
  bool get repeatOneEnabled => _repeatOneEnabled;
  double get volume => _volume;
  String? get currentTrackPath => _currentTrackPath;
  bool isCurrentTrack(int index) =>
      _currentIndex == index && _currentIndex != -1;
  bool isTrackPlaying(int index) => isCurrentTrack(index) && _playing;
  bool isCurrentTrackPath(String path) =>
      _currentTrackPath != null && _currentTrackPath == path;

  void _setupStreams() {
    _subscriptions.add(
      _audioHandler.playbackState.listen((state) {
        final nextPlaying = state.playing;
        final nextBuffered = state.bufferedPosition;
        final nextProcessingState = _mapProcessingState(state.processingState);
        final nextPosition = state.updatePosition;

        var changed =
            _playing != nextPlaying ||
            _bufferedPosition != nextBuffered ||
            _processingState != nextProcessingState;

        _playing = nextPlaying;
        _bufferedPosition = nextBuffered;
        _processingState = nextProcessingState;

        if (_position != nextPosition) {
          _position = nextPosition;
          changed = true;
        }

        if (!_playing && nextPosition == Duration.zero) {
          _lastNotifiedPositionMs = 0;
        }

        if (changed) {
          notifyListeners();
        }
      }),
    );

    _subscriptions.add(
      AudioService.position.listen((pos) {
        // Throttle position UI updates to avoid excessive rebuilds.
        final posMs = pos.inMilliseconds;
        if ((posMs - _lastNotifiedPositionMs).abs() < 200) return;

        _position = pos;
        _lastNotifiedPositionMs = posMs;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _audioHandler.mediaItem.listen((item) {
        if (item == null) return;
        final isTrackChanged = _currentTrackPath != item.id;
        _duration = item.duration ?? Duration.zero;
        if (isTrackChanged) {
          _position = Duration.zero;
          _lastNotifiedPositionMs = 0;
        }
        _syncCurrentIndexByPath(item.id);
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _audioHandler.queue.listen((_) {
        final currentId = _audioHandler.mediaItem.value?.id;
        if (currentId != null) {
          final prevIndex = _currentIndex;
          _syncCurrentIndexByPath(currentId);
          if (prevIndex != _currentIndex) {
            notifyListeners();
          }
        }
      }),
    );

    _subscriptions.add(
      _audioHandler.shuffleEnabledStream.listen((enabled) {
        if (_shuffleEnabled == enabled) return;
        _shuffleEnabled = enabled;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _audioHandler.loopModeStream.listen((mode) {
        final nextRepeatOne = mode == LoopMode.one;
        if (_repeatOneEnabled == nextRepeatOne) return;
        _repeatOneEnabled = nextRepeatOne;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _audioHandler.volumeStream.listen((value) {
        if ((_volume - value).abs() < 0.001) return;
        _volume = value;
        notifyListeners();
      }),
    );
  }

  void _syncCurrentIndexByPath(String path) {
    _currentTrackPath = path;
    final idx = _localMusicProvider.selectedFiles.indexWhere(
      (file) => file.path == path,
    );
    _currentIndex = idx;
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
    await playFromTracks(_localMusicProvider.selectedFiles, initialIndex: index);
  }

  Future<void> playPause() async {
    await playPauseFromTracks(_localMusicProvider.selectedFiles);
  }

  Future<void> toggleTrackAt(int index) async {
    await toggleTrackFromTracks(_localMusicProvider.selectedFiles, index);
  }

  Future<void> playFromTracks(
    List<File> tracks, {
    required int initialIndex,
  }) async {
    if (tracks.isEmpty) return;

    final safeIndex = initialIndex.clamp(0, tracks.length - 1);
    final items = tracks
        .map(
          (file) =>
              MediaItem(id: file.path, album: '', title: p.basename(file.path)),
        )
        .toList();

    _activeQueuePaths = tracks.map((file) => file.path).toList();
    await _audioHandler.setQueue(items, initialIndex: safeIndex);
    await _audioHandler.play();

    _syncCurrentIndexByPath(tracks[safeIndex].path);
    _position = Duration.zero;
    _lastNotifiedPositionMs = 0;
    notifyListeners();
  }

  Future<void> playPauseFromTracks(List<File> tracks) async {
    if (tracks.isEmpty) return;

    if (!_audioHandler.hasQueue ||
        _audioHandler.mediaItem.value == null ||
        _audioHandler.currentQueueIndex == null ||
        !_isQueueMatchingTracks(tracks)) {
      await playFromTracks(
        tracks,
        initialIndex: _resolveStartIndexForTracks(tracks),
      );
      return;
    }

    final isPlaying = _audioHandler.playbackState.value.playing;
    if (isPlaying) {
      await _audioHandler.pause();
    } else {
      await _audioHandler.play();
    }
  }

  Future<void> toggleTrackFromTracks(List<File> tracks, int index) async {
    if (index < 0 || index >= tracks.length) return;

    final targetPath = tracks[index].path;
    if (isCurrentTrackPath(targetPath) && _isQueueMatchingTracks(tracks)) {
      await playPauseFromTracks(tracks);
      return;
    }

    await playFromTracks(tracks, initialIndex: index);
  }

  bool _isQueueMatchingTracks(List<File> tracks) {
    if (_activeQueuePaths.length != tracks.length) return false;
    for (var i = 0; i < tracks.length; i++) {
      if (_activeQueuePaths[i] != tracks[i].path) {
        return false;
      }
    }
    return true;
  }

  int _resolveStartIndexForTracks(List<File> tracks) {
    if (_currentTrackPath == null) return 0;
    final index = tracks.indexWhere((file) => file.path == _currentTrackPath);
    return index == -1 ? 0 : index;
  }

  Future<void> seek(Duration newPosition) async {
    _position = newPosition;
    notifyListeners();
    await _audioHandler.seek(newPosition);
  }

  Future<void> setVolume(double value) async {
    await _audioHandler.setVolumeLevel(value);
  }

  Future<void> toggleShuffle() async {
    await _audioHandler.toggleShuffleMode();
  }

  Future<void> toggleRepeatOne() async {
    await _audioHandler.toggleRepeatOneMode();
  }

  Future<void> skipToNext() async {
    if (!_audioHandler.hasQueue) return;
    await _audioHandler.skipToNext();
  }

  Future<void> skipToPrevious() async {
    if (!_audioHandler.hasQueue) return;
    await _audioHandler.skipToPrevious();
  }

  Future<void> skipToNextFromTracks(List<File> tracks) async {
    if (tracks.isEmpty) return;
    if (!_isQueueMatchingTracks(tracks)) {
      await playFromTracks(tracks, initialIndex: 0);
      return;
    }
    await _audioHandler.skipToNext();
  }

  Future<void> skipToPreviousFromTracks(List<File> tracks) async {
    if (tracks.isEmpty) return;
    if (!_isQueueMatchingTracks(tracks)) {
      await playFromTracks(tracks, initialIndex: tracks.length - 1);
      return;
    }
    await _audioHandler.skipToPrevious();
  }

  Future<void> stop() async {
    await _audioHandler.stop();
    _currentIndex = -1;
    _currentTrackPath = null;
    _activeQueuePaths = <String>[];
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
