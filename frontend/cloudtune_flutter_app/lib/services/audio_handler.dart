import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  static const String toggleLikeAction = 'toggle_like';

  final AudioPlayer _player = AudioPlayer();
  bool _hasPreparedShuffleForCurrentQueue = false;
  bool _isDelayedAdvanceInProgress = false;
  Future<void> _opChain = Future<void>.value();
  DateTime? _lastSpeedAuditAt;
  Duration? _lastSpeedAuditPosition;
  int _speedDriftStrikes = 0;
  bool _currentTrackLiked = false;
  Future<bool> Function(String trackPath)? _onToggleLike;
  bool Function(String trackPath)? _isTrackLiked;

  bool get shuffleEnabled => _player.shuffleModeEnabled;
  Stream<bool> get shuffleEnabledStream => _player.shuffleModeEnabledStream;
  LoopMode get loopMode => _player.loopMode;
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;
  double get volume => _player.volume;
  Stream<double> get volumeStream => _player.volumeStream;
  int? get currentQueueIndex => _player.currentIndex;
  bool get hasQueue => queue.value.isNotEmpty;

  void bindLikeHandlers({
    required Future<bool> Function(String trackPath) onToggleLike,
    required bool Function(String trackPath) isTrackLiked,
  }) {
    _onToggleLike = onToggleLike;
    _isTrackLiked = isTrackLiked;
    refreshLikeState();
  }

  void refreshLikeState() {
    final nextLiked = _resolveCurrentTrackLiked();
    if (_currentTrackLiked == nextLiked) return;
    _currentTrackLiked = nextLiked;
    playbackState.add(_mapPlaybackState(_player));
  }

  bool _resolveCurrentTrackLiked() {
    final currentPath = mediaItem.value?.id;
    final isTrackLiked = _isTrackLiked;
    if (currentPath == null || isTrackLiked == null) return false;
    return isTrackLiked(currentPath);
  }

  Future<T> _runSerialized<T>(Future<T> Function() action) {
    if (!Platform.isWindows) {
      return action();
    }
    final run = _opChain.then((_) => action());
    _opChain = run.then((_) {}).catchError((_) {});
    return run;
  }

  MyAudioHandler() {
    unawaited(_configureAudioSession());

    // Keep playback rate stable even if platform media session requests speed changes.
    _player.setSpeed(1.0);

    _player.playbackEventStream.listen((_) {
      _auditPlaybackSpeed();
      playbackState.add(_mapPlaybackState(_player));
    }, onError: (Object error, StackTrace stackTrace) {});

    _player.processingStateStream.listen((_) {
      unawaited(_handleDelayedAdvanceIfNeeded());
      playbackState.add(_mapPlaybackState(_player));
    });

    _player.speedStream.listen((speed) {
      if ((speed - 1.0).abs() > 0.001) {
        unawaited(_player.setSpeed(1.0));
      }
    });

    _player.durationStream.listen((duration) {
      final currentItem = mediaItem.value;
      if (currentItem != null && duration != null) {
        mediaItem.add(currentItem.copyWith(duration: duration));
      }
    });

    _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < queue.value.length) {
        mediaItem.add(queue.value[index]);
        refreshLikeState();
      }
    });
  }

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        if (_player.playing) {
          unawaited(pause());
        }
        return;
      }

      // Не возобновляем автоматически, пользователь сам снимает с паузы из уведомления.
    });

    session.becomingNoisyEventStream.listen((_) {
      if (_player.playing) {
        unawaited(pause());
      }
    });
  }

  @override
  Future<void> play() async {
    await _runSerialized(() async {
      if (_player.speed != 1.0) {
        await _player.setSpeed(1.0);
      }
      // just_audio play() may complete only when playback ends; do not block
      // serialized command queue on this future.
      unawaited(_player.play());
    });
  }

  @override
  Future<void> pause() => _runSerialized(() => _player.pause());

  @override
  Future<void> stop() async {
    await _runSerialized(() => _player.stop());
  }

  @override
  Future<void> seek(Duration position) =>
      _runSerialized(() => _player.seek(position));

  @override
  Future<void> skipToNext() async {
    await _runSerialized(() async {
      final total = queue.value.length;
      if (total == 0) return;
      await _player.setSpeed(1.0);

      if (_player.hasNext) {
        await _player.seekToNext();
      } else {
        final fallbackIndex = _player.shuffleModeEnabled
            ? (_player.effectiveIndices?.first ?? 0)
            : 0;
        await _player.seek(null, index: fallbackIndex);
      }
      playbackState.add(_mapPlaybackState(_player));
    });
  }

  @override
  Future<void> skipToPrevious() async {
    await _runSerialized(() async {
      final total = queue.value.length;
      if (total == 0) return;
      await _player.setSpeed(1.0);

      if (_player.hasPrevious) {
        await _player.seekToPrevious();
      } else {
        final fallbackIndex = _player.shuffleModeEnabled
            ? (_player.effectiveIndices?.last ?? (total - 1))
            : (total - 1);
        await _player.seek(null, index: fallbackIndex);
      }
      playbackState.add(_mapPlaybackState(_player));
    });
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _runSerialized(() async {
      if (index < 0 || index >= queue.value.length) return;
      await _player.setSpeed(1.0);
      await _player.seek(null, index: index);
    });
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _runSerialized(() async {
      await _player.setSpeed(1.0);
      playbackState.add(_mapPlaybackState(_player));
    });
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name != toggleLikeAction) {
      return super.customAction(name, extras);
    }

    final currentPath = mediaItem.value?.id;
    final onToggleLike = _onToggleLike;
    if (currentPath == null || onToggleLike == null) return null;

    final liked = await onToggleLike(currentPath);
    if (_currentTrackLiked != liked) {
      _currentTrackLiked = liked;
      playbackState.add(_mapPlaybackState(_player));
    }

    return <String, dynamic>{'liked': liked, 'path': currentPath};
  }

  Future<void> setVolumeLevel(double value) async {
    await _runSerialized(() async {
      final safeValue = value.clamp(0.0, 1.0);
      await _player.setVolume(safeValue);
      playbackState.add(_mapPlaybackState(_player));
    });
  }

  Future<void> toggleShuffleMode() async {
    await _runSerialized(() async {
      final nextState = !_player.shuffleModeEnabled;
      await _player.setShuffleModeEnabled(nextState);
      if (nextState &&
          !_hasPreparedShuffleForCurrentQueue &&
          _player.audioSource is ConcatenatingAudioSource) {
        await _player.shuffle();
        _hasPreparedShuffleForCurrentQueue = true;
      }
      playbackState.add(_mapPlaybackState(_player));
    });
  }

  Future<void> toggleRepeatOneMode() async {
    await _runSerialized(() async {
      final nextMode = _player.loopMode == LoopMode.one
          ? LoopMode.off
          : LoopMode.one;
      await _player.setLoopMode(nextMode);
      playbackState.add(_mapPlaybackState(_player));
    });
  }

  Future<void> setQueue(List<MediaItem> items, {int initialIndex = 0}) async {
    await _runSerialized(() async {
      if (items.isEmpty) return;

      final safeInitialIndex = initialIndex.clamp(0, items.length - 1);
      _hasPreparedShuffleForCurrentQueue = false;
      if (_player.shuffleModeEnabled) {
        await _player.setShuffleModeEnabled(false);
      }
      queue.add(items);
      await _player.setSpeed(1.0);

      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: items
              .map((item) => AudioSource.file(item.id, tag: item))
              .toList(),
        ),
        initialIndex: safeInitialIndex,
        initialPosition: Duration.zero,
      );

      mediaItem.add(items[safeInitialIndex]);
      refreshLikeState();
      playbackState.add(_mapPlaybackState(_player));
    });
  }

  Future<void> _handleDelayedAdvanceIfNeeded() async {
    if (_isDelayedAdvanceInProgress) return;
    if (_player.processingState != ProcessingState.completed) return;
    if (_player.loopMode == LoopMode.one) return;
    final total = queue.value.length;
    if (total <= 1) return;

    _isDelayedAdvanceInProgress = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_player.processingState != ProcessingState.completed) return;
      if (_player.hasNext) {
        await _player.seekToNext();
      } else {
        final fallbackIndex = _player.shuffleModeEnabled
            ? (_player.effectiveIndices?.first ?? 0)
            : 0;
        await _player.seek(null, index: fallbackIndex);
      }
      unawaited(_player.play());
    } finally {
      _isDelayedAdvanceInProgress = false;
    }
  }

  void _auditPlaybackSpeed() {
    if (!Platform.isWindows) return;
    if (!_player.playing || _player.processingState != ProcessingState.ready) {
      _lastSpeedAuditAt = null;
      _lastSpeedAuditPosition = null;
      _speedDriftStrikes = 0;
      return;
    }

    final now = DateTime.now();
    final currentPosition = _player.position;
    final previousAuditAt = _lastSpeedAuditAt;
    final previousAuditPosition = _lastSpeedAuditPosition;

    _lastSpeedAuditAt = now;
    _lastSpeedAuditPosition = currentPosition;

    if (previousAuditAt == null || previousAuditPosition == null) return;

    final elapsedMs = now.difference(previousAuditAt).inMilliseconds;
    if (elapsedMs < 1000) return;

    final advancedMs =
        currentPosition.inMilliseconds - previousAuditPosition.inMilliseconds;

    // Ignore manual seeks and track changes.
    if (advancedMs < 0 || advancedMs.abs() > elapsedMs * 5) {
      _speedDriftStrikes = 0;
      return;
    }

    final ratio = advancedMs / elapsedMs;
    final unstable = ratio < 0.7 || ratio > 1.3;
    if (!unstable) {
      _speedDriftStrikes = 0;
      return;
    }

    _speedDriftStrikes += 1;
    if (_speedDriftStrikes < 2) return;

    _speedDriftStrikes = 0;
    unawaited(_player.setSpeed(1.0));
  }

  PlaybackState _mapPlaybackState(AudioPlayer player) {
    final likeControl = MediaControl.custom(
      androidIcon: _currentTrackLiked
          ? 'drawable/ic_notification_like_on'
          : 'drawable/ic_notification_like_off',
      label: _currentTrackLiked ? 'Unlike' : 'Like',
      name: toggleLikeAction,
      extras: <String, dynamic>{'liked': _currentTrackLiked},
    );

    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        likeControl,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: 1.0,
      queueIndex: player.currentIndex,
    );
  }

  @override
  Future<void> onTaskRemoved() async {
    // При сворачивании/убийстве UI оставляем сервис живым, но ставим воспроизведение на паузу.
    if (_player.playing) {
      await pause();
    }
  }
}
