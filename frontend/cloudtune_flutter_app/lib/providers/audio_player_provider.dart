import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import '../providers/local_music_provider.dart';

class AudioPlayerProvider with ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  late LocalMusicProvider _localMusicProvider;
  int _currentIndex = -1;
  
  AudioPlayerProvider(this._localMusicProvider) {
    _setupAudioService();
  }
  
  void updateLocalMusicProvider(LocalMusicProvider localMusicProvider) {
    _localMusicProvider = localMusicProvider;
    notifyListeners();
  }
  
  List<File> get audioFiles => _localMusicProvider.selectedFiles;
  
  ProcessingState get processingState => _player.processingState;
  bool get playing => _player.playing;
  Duration get position => _player.position;
  Duration get bufferedPosition => _player.bufferedPosition;
  Duration get duration => _player.duration ?? Duration.zero;
  
  void _setupAudioService() {
    _player.processingStateStream.listen((state) {
      notifyListeners();
    });
    
    _player.playingStream.listen((playing) {
      notifyListeners();
    });
    
    _player.positionStream.listen((position) {
      notifyListeners();
    });
  }
  
  Future<void> playAudioAt(int index) async {
    if (index >= 0 && index < _localMusicProvider.selectedFiles.length) {
      _currentIndex = index;
      final filePath = _localMusicProvider.selectedFiles[index].path;
      
      try {
        await _player.setFilePath(filePath);
        await _player.play();
        notifyListeners();
      } catch (e) {
        // Log error in production
      }
    }
  }
  
  Future<void> playPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    notifyListeners();
  }
  
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    notifyListeners();
  }
  
  Future<void> stop() async {
    await _player.stop();
    _currentIndex = -1;
    notifyListeners();
  }
  
  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
  
  // Get current playing index
  int get currentIndex => _currentIndex;
  
  // Check if a specific track is currently playing
  bool isCurrentTrack(int index) {
    return _currentIndex == index && _currentIndex != -1;
  }
}