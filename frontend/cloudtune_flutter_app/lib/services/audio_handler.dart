import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  bool _hasPreparedShuffleForCurrentQueue = false;

  bool get shuffleEnabled => _player.shuffleModeEnabled;
  Stream<bool> get shuffleEnabledStream => _player.shuffleModeEnabledStream;
  LoopMode get loopMode => _player.loopMode;
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;
  double get volume => _player.volume;
  Stream<double> get volumeStream => _player.volumeStream;
  int? get currentQueueIndex => _player.currentIndex;
  bool get hasQueue => queue.value.isNotEmpty;

  MyAudioHandler() {
    // Keep playback rate stable even if platform media session requests speed changes.
    _player.setSpeed(1.0);

    _player.playbackEventStream.listen(
      (_) => playbackState.add(_mapPlaybackState(_player)),
      onError: (Object error, StackTrace stackTrace) {},
    );

    _player.processingStateStream.listen((_) {
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
      }
    });
  }

  @override
  Future<void> play() async {
    if (_player.speed != 1.0) {
      await _player.setSpeed(1.0);
    }
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    final total = queue.value.length;
    if (total == 0) return;
    await _player.setSpeed(1.0);

    if (_player.hasNext) {
      await _player.seekToNext();
    } else {
      final fallbackIndex = _player.shuffleModeEnabled
          ? (_player.effectiveIndices?.first ?? 0)
          : 0;
      await _player.seek(Duration.zero, index: fallbackIndex);
    }
    playbackState.add(_mapPlaybackState(_player));
  }

  @override
  Future<void> skipToPrevious() async {
    final total = queue.value.length;
    if (total == 0) return;
    await _player.setSpeed(1.0);

    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      final fallbackIndex = _player.shuffleModeEnabled
          ? (_player.effectiveIndices?.last ?? (total - 1))
          : (total - 1);
      await _player.seek(Duration.zero, index: fallbackIndex);
    }
    playbackState.add(_mapPlaybackState(_player));
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await _player.setSpeed(1.0);
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(1.0);
    playbackState.add(_mapPlaybackState(_player));
  }

  Future<void> setVolumeLevel(double value) async {
    final safeValue = value.clamp(0.0, 1.0);
    await _player.setVolume(safeValue);
    playbackState.add(_mapPlaybackState(_player));
  }

  Future<void> toggleShuffleMode() async {
    final nextState = !_player.shuffleModeEnabled;
    await _player.setShuffleModeEnabled(nextState);
    if (nextState &&
        !_hasPreparedShuffleForCurrentQueue &&
        _player.audioSource is ConcatenatingAudioSource) {
      await _player.shuffle();
      _hasPreparedShuffleForCurrentQueue = true;
    }
    playbackState.add(_mapPlaybackState(_player));
  }

  Future<void> toggleRepeatOneMode() async {
    final nextMode = _player.loopMode == LoopMode.one
        ? LoopMode.off
        : LoopMode.one;
    await _player.setLoopMode(nextMode);
    playbackState.add(_mapPlaybackState(_player));
  }

  Future<void> setQueue(List<MediaItem> items, {int initialIndex = 0}) async {
    if (items.isEmpty) return;

    final safeInitialIndex = initialIndex.clamp(0, items.length - 1);
    _hasPreparedShuffleForCurrentQueue = false;
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

    if (_player.shuffleModeEnabled && !_hasPreparedShuffleForCurrentQueue) {
      await _player.shuffle();
      _hasPreparedShuffleForCurrentQueue = true;
    }

    mediaItem.add(items[safeInitialIndex]);
    playbackState.add(_mapPlaybackState(_player));
  }

  PlaybackState _mapPlaybackState(AudioPlayer player) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      androidCompactActionIndices: const [0, 1, 3],
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
}
