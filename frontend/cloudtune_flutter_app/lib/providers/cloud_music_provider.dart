import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/api_service.dart';

class CloudMusicProvider with ChangeNotifier {
  CloudMusicProvider({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  static const int _libraryPageSize = 80;
  static const int _playlistsPageSize = 40;
  static const int _playlistSongsPageSize = 80;

  final ApiService _apiService;

  int? _parseInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  List<Track> _tracks = <Track>[];
  List<Playlist> _playlists = <Playlist>[];
  final Map<int, List<Track>> _playlistTracks = <int, List<Track>>{};
  final Map<int, bool> _playlistLoading = <int, bool>{};
  final Map<int, bool> _playlistHasMore = <int, bool>{};
  final Map<int, int> _playlistOffset = <int, int>{};
  final Map<int, String> _playlistSearchQuery = <int, String>{};

  bool _isLoading = false;
  bool _isLibraryLoading = false;
  bool _isPlaylistsLoading = false;
  bool _hasMoreTracks = true;
  bool _hasMorePlaylists = true;
  int _tracksOffset = 0;
  int _tracksTotal = 0;
  int _playlistsOffset = 0;
  String _tracksSearchQuery = '';
  String _playlistsSearchQuery = '';
  int _usedBytes = 0;
  int _quotaBytes = 3 * 1024 * 1024 * 1024;

  List<Track> get tracks => _tracks;
  List<Playlist> get playlists => _playlists;
  bool get isLoading => _isLoading;
  bool get isLibraryLoading => _isLibraryLoading;
  bool get isPlaylistsLoading => _isPlaylistsLoading;
  bool get hasMoreTracks => _hasMoreTracks;
  bool get hasMorePlaylists => _hasMorePlaylists;
  int get tracksTotal => _tracksTotal;
  String get tracksSearchQuery => _tracksSearchQuery;
  String get playlistsSearchQuery => _playlistsSearchQuery;
  int get usedBytes => _usedBytes;
  int get quotaBytes => _quotaBytes;
  int get remainingBytes =>
      (_quotaBytes - _usedBytes).clamp(0, _quotaBytes).toInt();

  bool isPlaylistTracksLoading(int playlistId) =>
      _playlistLoading[playlistId] == true;

  bool hasMorePlaylistTracks(int playlistId) =>
      _playlistHasMore[playlistId] ?? true;

  String playlistTracksSearchQuery(int playlistId) =>
      _playlistSearchQuery[playlistId] ?? '';

  List<Track> getTracksForPlaylist(int playlistId) {
    return _playlistTracks[playlistId] ?? const <Track>[];
  }

  Future<void> refreshCloudData() async {
    await Future.wait([
      fetchUserLibrary(reset: true),
      fetchUserPlaylists(reset: true),
      fetchStorageUsage(),
    ]);
  }

  Future<void> fetchUserLibrary({
    bool reset = false,
    String? search,
    int limit = _libraryPageSize,
  }) async {
    final normalizedSearch = search?.trim();
    if (normalizedSearch != null && normalizedSearch != _tracksSearchQuery) {
      _tracksSearchQuery = normalizedSearch;
      reset = true;
    }

    if (_isLibraryLoading) return;
    if (!reset && !_hasMoreTracks) return;

    if (reset) {
      _tracks = <Track>[];
      _tracksOffset = 0;
      _tracksTotal = 0;
      _hasMoreTracks = true;
    }

    _isLibraryLoading = true;
    _refreshLoadingFlag();
    notifyListeners();

    try {
      final result = await _apiService.getUserLibrary(
        limit: limit,
        offset: _tracksOffset,
        search: _tracksSearchQuery,
      );

      if (result['success'] != true) {
        throw Exception(result['message']);
      }

      final items = (result['songs'] as List<dynamic>)
          .map((songData) => Track.fromJson(songData as Map<String, dynamic>))
          .toList();

      if (reset) {
        _tracks = items;
      } else {
        final seenIds = _tracks.map((item) => item.id).toSet();
        for (final item in items) {
          if (seenIds.add(item.id)) {
            _tracks.add(item);
          }
        }
      }

      _tracksTotal = _parseInt(result['total']) ?? _tracks.length;
      _tracksOffset = (_tracksOffset + items.length).clamp(0, 1 << 30);
      _hasMoreTracks = result['has_more'] == true;
    } catch (e) {
      debugPrint('Error fetching user library: $e');
    } finally {
      _isLibraryLoading = false;
      _refreshLoadingFlag();
      notifyListeners();
    }
  }

  Future<void> loadMoreUserLibrary() async {
    await fetchUserLibrary();
  }

  Future<void> fetchUserPlaylists({
    bool reset = false,
    String? search,
    int limit = _playlistsPageSize,
  }) async {
    final normalizedSearch = search?.trim();
    if (normalizedSearch != null && normalizedSearch != _playlistsSearchQuery) {
      _playlistsSearchQuery = normalizedSearch;
      reset = true;
    }

    if (_isPlaylistsLoading) return;
    if (!reset && !_hasMorePlaylists) return;

    if (reset) {
      _playlists = <Playlist>[];
      _playlistsOffset = 0;
      _hasMorePlaylists = true;
    }

    _isPlaylistsLoading = true;
    _refreshLoadingFlag();
    notifyListeners();

    try {
      final result = await _apiService.getUserPlaylists(
        limit: limit,
        offset: _playlistsOffset,
        search: _playlistsSearchQuery,
      );

      if (result['success'] != true) {
        throw Exception(result['message']);
      }

      final items = (result['playlists'] as List<dynamic>)
          .map(
            (playlistData) =>
                Playlist.fromJson(playlistData as Map<String, dynamic>),
          )
          .toList();

      if (reset) {
        _playlists = items;
      } else {
        final seenIds = _playlists.map((item) => item.id).toSet();
        for (final item in items) {
          if (seenIds.add(item.id)) {
            _playlists.add(item);
          }
        }
      }

      _playlistsOffset = (_playlistsOffset + items.length).clamp(0, 1 << 30);
      _hasMorePlaylists = result['has_more'] == true;
    } catch (e) {
      debugPrint('Error fetching user playlists: $e');
    } finally {
      _isPlaylistsLoading = false;
      _refreshLoadingFlag();
      notifyListeners();
    }
  }

  Future<void> loadMoreUserPlaylists() async {
    await fetchUserPlaylists();
  }

  Future<void> fetchPlaylistTracks(
    int playlistId, {
    bool reset = false,
    String? search,
    int limit = _playlistSongsPageSize,
  }) async {
    final normalizedSearch = search?.trim();
    final currentSearch = _playlistSearchQuery[playlistId] ?? '';
    if (normalizedSearch != null && normalizedSearch != currentSearch) {
      _playlistSearchQuery[playlistId] = normalizedSearch;
      reset = true;
    }

    final isLoading = _playlistLoading[playlistId] == true;
    final hasMore = _playlistHasMore[playlistId] ?? true;
    if (isLoading) return;
    if (!reset && !hasMore) return;

    if (reset) {
      _playlistTracks[playlistId] = <Track>[];
      _playlistOffset[playlistId] = 0;
      _playlistHasMore[playlistId] = true;
    }

    _playlistLoading[playlistId] = true;
    _refreshLoadingFlag();
    notifyListeners();

    try {
      final result = await _apiService.getPlaylistSongs(
        playlistId,
        limit: limit,
        offset: _playlistOffset[playlistId] ?? 0,
        search: _playlistSearchQuery[playlistId] ?? '',
      );

      if (result['success'] != true) {
        throw Exception(result['message']);
      }

      final items = (result['songs'] as List<dynamic>)
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();

      final current = _playlistTracks[playlistId] ?? <Track>[];
      if (reset) {
        _playlistTracks[playlistId] = items;
      } else {
        final seenIds = current.map((item) => item.id).toSet();
        for (final item in items) {
          if (seenIds.add(item.id)) {
            current.add(item);
          }
        }
        _playlistTracks[playlistId] = current;
      }

      final offset = (_playlistOffset[playlistId] ?? 0) + items.length;
      _playlistOffset[playlistId] = offset.clamp(0, 1 << 30);
      _playlistHasMore[playlistId] = result['has_more'] == true;
    } catch (e) {
      debugPrint('Error fetching playlist tracks: $e');
    } finally {
      _playlistLoading[playlistId] = false;
      _refreshLoadingFlag();
      notifyListeners();
    }
  }

  Future<void> loadMorePlaylistTracks(int playlistId) async {
    await fetchPlaylistTracks(playlistId);
  }

  void invalidatePlaylistTracks([int? playlistId]) {
    if (playlistId == null) {
      _playlistTracks.clear();
      _playlistLoading.clear();
      _playlistHasMore.clear();
      _playlistOffset.clear();
      _playlistSearchQuery.clear();
    } else {
      _playlistTracks.remove(playlistId);
      _playlistLoading.remove(playlistId);
      _playlistHasMore.remove(playlistId);
      _playlistOffset.remove(playlistId);
      _playlistSearchQuery.remove(playlistId);
    }
    notifyListeners();
  }

  Future<bool> downloadTrack(
    int trackId,
    String savePath, {
    CancelToken? cancelToken,
  }) async {
    try {
      final result = await _apiService.downloadFile(
        trackId,
        savePath,
        cancelToken: cancelToken,
      );

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

  Future<void> fetchStorageUsage() async {
    try {
      final result = await _apiService.getStorageUsage();
      if (result['success'] == true) {
        _usedBytes = (result['used_bytes'] as num).toInt();
        _quotaBytes = (result['quota_bytes'] as num).toInt();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching storage usage: $e');
    }
  }

  void _refreshLoadingFlag() {
    _isLoading =
        _isLibraryLoading ||
        _isPlaylistsLoading ||
        _playlistLoading.values.any((value) => value);
  }
}
