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
  late final VoidCallback _localMusicProviderListener;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  int _currentIndex = -1;
  String? _currentTrackPath;
  List<String> _activeQueuePaths = <String>[];
  List<String> _queueSourcePaths = <String>[];
  bool _sessionShuffleQueuePrepared = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _duration = Duration.zero;
  ProcessingState _processingState = ProcessingState.idle;
  int _lastNotifiedPositionMs = 0;
  bool _shuffleEnabled = false;
  bool _repeatOneEnabled = false;
  double _volume = 0.7;
  final int _shuffleSessionSalt = DateTime.now().microsecondsSinceEpoch;

  AudioPlayerProvider(this._localMusicProvider, this._audioHandler) {
    _shuffleEnabled = false;
    _repeatOneEnabled = _audioHandler.loopMode == LoopMode.one;
    _volume = _audioHandler.volume;
    _localMusicProviderListener = _handleLocalMusicProviderChanged;
    _localMusicProvider.addListener(_localMusicProviderListener);
    _audioHandler.bindLikeHandlers(
      isTrackLiked: _localMusicProvider.isTrackLiked,
    );
    _setupStreams();
  }

  void updateLocalMusicProvider(LocalMusicProvider localMusicProvider) {
    if (!identical(_localMusicProvider, localMusicProvider)) {
      _localMusicProvider.removeListener(_localMusicProviderListener);
      _localMusicProvider = localMusicProvider;
      _localMusicProvider.addListener(_localMusicProviderListener);
      _audioHandler.bindLikeHandlers(
        isTrackLiked: _localMusicProvider.isTrackLiked,
      );
    }

    _localMusicProvider = localMusicProvider;
    final existingPaths = _localMusicProvider.selectedFiles
        .map((file) => file.path)
        .map(_normalizePath)
        .toSet();

    _activeQueuePaths = _activeQueuePaths
        .where((path) => existingPaths.contains(_normalizePath(path)))
        .toList();
    _queueSourcePaths = _queueSourcePaths
        .where((path) => existingPaths.contains(_normalizePath(path)))
        .toList();

    if (_currentTrackPath != null &&
        !existingPaths.contains(_normalizePath(_currentTrackPath!))) {
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

  void _handleLocalMusicProviderChanged() {
    _audioHandler.refreshLikeState();
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
  bool get hasActiveQueue => _audioHandler.hasQueue;
  bool isCurrentTrack(int index) =>
      _currentIndex == index && _currentIndex != -1;
  bool isTrackPlaying(int index) => isCurrentTrack(index) && _playing;
  bool isCurrentTrackPath(String path) =>
      _currentTrackPath != null && _pathsEqual(_currentTrackPath!, path);
  bool isCurrentQueueFromTracks(List<File> tracks) {
    if (!_audioHandler.hasQueue || tracks.isEmpty) return false;
    return _isQueueMatchingTracks(tracks);
  }

  String _normalizePath(String path) {
    final unified = path.replaceAll('/', '\\');
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return unified.toLowerCase();
    }
    return unified;
  }

  bool _pathsEqual(String left, String right) {
    return _normalizePath(left) == _normalizePath(right);
  }

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
        final isTrackChanged =
            _currentTrackPath == null ||
            !_pathsEqual(_currentTrackPath!, item.id);
        _duration = item.duration ?? Duration.zero;
        if (isTrackChanged) {
          _position = Duration.zero;
          _bufferedPosition = Duration.zero;
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
      (file) => _pathsEqual(file.path, path),
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
    await playFromTracks(
      _localMusicProvider.selectedFiles,
      initialIndex: index,
    );
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
    bool autoPlay = true,
    Duration? seekTo,
    bool preserveProgressUi = false,
  }) async {
    if (tracks.isEmpty) return;

    final playableTracks = tracks.where((file) => file.existsSync()).toList();
    if (playableTracks.isEmpty) return;

    _queueSourcePaths = playableTracks
        .map((file) => _normalizePath(file.path))
        .toList();

    final targetPath = tracks[initialIndex.clamp(0, tracks.length - 1)].path;
    final orderedTracks = _orderedTracksForQueue(playableTracks);
    var safeIndex = orderedTracks.indexWhere(
      (file) => _pathsEqual(file.path, targetPath),
    );
    if (safeIndex < 0) {
      safeIndex = initialIndex.clamp(0, orderedTracks.length - 1);
    }

    final items = orderedTracks
        .map(
          (file) =>
              MediaItem(id: file.path, album: '', title: p.basename(file.path)),
        )
        .toList();

    _activeQueuePaths = orderedTracks
        .map((file) => _normalizePath(file.path))
        .toList();
    if (!preserveProgressUi) {
      _duration = Duration.zero;
      _position = Duration.zero;
      _bufferedPosition = Duration.zero;
      _lastNotifiedPositionMs = 0;
    } else if (seekTo != null && seekTo > Duration.zero) {
      final safePosition = _duration > Duration.zero && seekTo > _duration
          ? _duration
          : seekTo;
      _position = safePosition;
    }
    notifyListeners();

    await _audioHandler.setQueue(items, initialIndex: safeIndex);
    if (seekTo != null && seekTo > Duration.zero) {
      await _audioHandler.seek(seekTo);
    }
    if (autoPlay) {
      await _audioHandler.play();
      await _ensurePlaybackStarted();
    }

    _syncCurrentIndexByPath(orderedTracks[safeIndex].path);
    notifyListeners();
  }

  Future<void> playPauseFromTracks(List<File> tracks) async {
    final hasPreparedQueue = _audioHandler.hasQueue;

    if (!hasPreparedQueue) {
      if (tracks.isEmpty) return;
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

    if (_isQueueMatchingTracks(tracks)) {
      final queueIndex = _indexInActiveQueue(targetPath);
      if (queueIndex >= 0) {
        _duration = Duration.zero;
        _position = Duration.zero;
        _bufferedPosition = Duration.zero;
        _lastNotifiedPositionMs = 0;
        notifyListeners();
        await _audioHandler.skipToQueueItem(queueIndex);
        await _audioHandler.play();
        await _ensurePlaybackStarted();
        _syncCurrentIndexByPath(targetPath);
        notifyListeners();
        return;
      }
    }

    await playFromTracks(tracks, initialIndex: index);
  }

  bool _isQueueMatchingTracks(List<File> tracks) {
    final playableTracks = tracks.where((file) => file.existsSync()).toList();
    final playablePaths = _orderedTracksForQueue(playableTracks)
        .where((file) => file.existsSync())
        .map((file) => _normalizePath(file.path))
        .toList();

    if (_activeQueuePaths.length != playablePaths.length) return false;
    for (var i = 0; i < playablePaths.length; i++) {
      if (_activeQueuePaths[i] != playablePaths[i]) {
        return false;
      }
    }
    return true;
  }

  int _indexInActiveQueue(String path) {
    final normalized = _normalizePath(path);
    return _activeQueuePaths.indexWhere((item) => item == normalized);
  }

  Future<void> _ensurePlaybackStarted() async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    if (_audioHandler.playbackState.value.playing) return;

    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (_audioHandler.playbackState.value.playing) return;
    await _audioHandler.play();
  }

  int _resolveStartIndexForTracks(List<File> tracks) {
    if (_currentTrackPath == null) return 0;
    final index = tracks.indexWhere(
      (file) => _pathsEqual(file.path, _currentTrackPath!),
    );
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
    final nextState = !_shuffleEnabled;
    _shuffleEnabled = nextState;
    notifyListeners();

    // Disable: keep current queue as-is.
    if (!nextState) return;
    // Enable: prepare shuffled queue only once per app session.
    if (_sessionShuffleQueuePrepared) return;

    final tracks = _queueSourceTracksFromLocalLibrary();
    final currentPath = _currentTrackPath;
    final shouldRebuildQueue =
        _audioHandler.hasQueue &&
        currentPath != null &&
        tracks.any((file) => _pathsEqual(file.path, currentPath));
    if (!shouldRebuildQueue || tracks.length <= 1) return;

    final currentIndexInTracks = tracks.indexWhere(
      (file) => _pathsEqual(file.path, currentPath),
    );
    if (currentIndexInTracks < 0) return;

    final wasPlaying = _audioHandler.playbackState.value.playing || _playing;
    final resumePosition = _position;
    await playFromTracks(
      tracks,
      initialIndex: currentIndexInTracks,
      autoPlay: wasPlaying,
      seekTo: resumePosition,
      preserveProgressUi: true,
    );
    _sessionShuffleQueuePrepared = true;
    if (wasPlaying && !_audioHandler.playbackState.value.playing) {
      await _audioHandler.play();
    }
  }

  List<File> _queueSourceTracksFromLocalLibrary() {
    final files = _localMusicProvider.selectedFiles;
    if (_queueSourcePaths.isEmpty || files.isEmpty) return files;

    final byPath = <String, File>{
      for (final file in files) _normalizePath(file.path): file,
    };
    final tracks = <File>[];
    for (final path in _queueSourcePaths) {
      final file = byPath[path];
      if (file != null) {
        tracks.add(file);
      }
    }
    return tracks.isEmpty ? files : tracks;
  }

  int _shuffleRank(String normalizedPath) {
    var hash = _shuffleSessionSalt;
    for (final unit in normalizedPath.codeUnits) {
      hash = 0x1fffffff & (hash + unit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= (hash >> 6);
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= (hash >> 11);
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return hash;
  }

  List<File> _orderedTracksForQueue(List<File> tracks) {
    if (!_shuffleEnabled) return List<File>.from(tracks);
    final ordered = List<File>.from(tracks);
    ordered.sort((a, b) {
      final aPath = _normalizePath(a.path);
      final bPath = _normalizePath(b.path);
      final rankA = _shuffleRank(aPath);
      final rankB = _shuffleRank(bPath);
      if (rankA != rankB) return rankA.compareTo(rankB);
      return aPath.compareTo(bPath);
    });
    return ordered;
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
    if (_audioHandler.hasQueue) {
      await _audioHandler.skipToNext();
      return;
    }
    if (tracks.isEmpty) return;
    await playFromTracks(tracks, initialIndex: 0);
  }

  Future<void> skipToPreviousFromTracks(List<File> tracks) async {
    if (_audioHandler.hasQueue) {
      await _audioHandler.skipToPrevious();
      return;
    }
    if (tracks.isEmpty) return;
    await playFromTracks(tracks, initialIndex: tracks.length - 1);
  }

  Future<void> stop() async {
    await _audioHandler.stop();
    _currentIndex = -1;
    _currentTrackPath = null;
    _activeQueuePaths = <String>[];
    _queueSourcePaths = <String>[];
    _sessionShuffleQueuePrepared = false;
    _playing = false;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _duration = Duration.zero;
    _processingState = ProcessingState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _localMusicProvider.removeListener(_localMusicProviderListener);
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }
}
