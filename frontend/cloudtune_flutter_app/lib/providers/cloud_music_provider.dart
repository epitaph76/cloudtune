import 'package:flutter/foundation.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../services/api_service.dart';

class CloudMusicProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  
  List<Track> _tracks = [];
  List<Playlist> _playlists = [];
  bool _isLoading = false;
  
  List<Track> get tracks => _tracks;
  List<Playlist> get playlists => _playlists;
  bool get isLoading => _isLoading;

  Future<void> fetchUserLibrary() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final result = await _apiService.getUserLibrary();
      
      if (result['success']) {
        _tracks = (result['songs'] as List)
            .map((songData) => Track.fromJson(songData))
            .toList();
      } else {
        throw Exception(result['message']);
      }
    } catch (e) {
      debugPrint('Error fetching user library: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchUserPlaylists() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final result = await _apiService.getUserPlaylists();
      
      if (result['success']) {
        _playlists = (result['playlists'] as List)
            .map((playlistData) => Playlist.fromJson(playlistData))
            .toList();
      } else {
        throw Exception(result['message']);
      }
    } catch (e) {
      debugPrint('Error fetching user playlists: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> downloadTrack(int trackId, String savePath) async {
    try {
      final result = await _apiService.downloadFile(trackId, savePath);
      
      if (result['success']) {
        return true;
      } else {
        throw Exception(result['message']);
      }
    } catch (e) {
      debugPrint('Error downloading track: $e');
      return false;
    }
  }

  List<Track> getTracksForPlaylist(int playlistId) {
    // В реальном приложении этот метод должен запрашивать список треков для конкретного плейлиста
    // Сейчас возвращаем все треки
    return _tracks;
  }
}