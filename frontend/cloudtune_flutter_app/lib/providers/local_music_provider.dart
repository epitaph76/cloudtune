import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class LocalPlaylist {
  LocalPlaylist({
    required this.id,
    required this.name,
    required this.trackPaths,
  });

  final String id;
  final String name;
  final Set<String> trackPaths;

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) {
    return LocalPlaylist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      trackPaths: Set<String>.from(json['track_paths'] as List? ?? const []),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'track_paths': trackPaths.toList()};
  }
}

class LocalMusicProvider with ChangeNotifier {
  static const String _filesKey = 'selected_audio_files';
  static const String _playlistsKey = 'selected_audio_playlists';

  List<File> _selectedFiles = [];
  List<LocalPlaylist> _playlists = [];

  LocalMusicProvider() {
    _loadSavedState();
  }

  List<File> get selectedFiles => _selectedFiles;
  List<LocalPlaylist> get playlists => _playlists;
  int get fileCount => _selectedFiles.length;

  Future<void> _loadSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final filesJson = prefs.getString(_filesKey);
      if (filesJson != null) {
        final filePaths = List<String>.from(json.decode(filesJson));
        _selectedFiles = [];
        for (final path in filePaths) {
          final file = File(path);
          if (await file.exists()) {
            _selectedFiles.add(file);
          }
        }
      }

      final playlistsJson = prefs.getString(_playlistsKey);
      if (playlistsJson != null) {
        final decoded = List<Map<String, dynamic>>.from(
          (json.decode(playlistsJson) as List).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        _playlists = decoded.map(LocalPlaylist.fromJson).toList();
      }

      await _deduplicateSelectedFilesAndRepairPlaylists();
      _cleanupPlaylists();
      await _saveFiles();
      await _savePlaylists();
      notifyListeners();
    } catch (_) {
      // Keep app running even if cache is corrupted.
    }
  }

  Future<void> addFiles(List<File> files) async {
    final existingPaths = _selectedFiles.map((file) => file.path).toSet();
    for (final file in files) {
      if (!existingPaths.contains(file.path)) {
        _selectedFiles.add(file);
        existingPaths.add(file.path);
      }
    }
    await _deduplicateSelectedFilesAndRepairPlaylists();
    _cleanupPlaylists();
    await _saveFiles();
    await _savePlaylists();
    notifyListeners();
  }

  Future<void> refreshLocalLibrary() async {
    final kept = <File>[];
    for (final file in _selectedFiles) {
      if (await file.exists()) {
        kept.add(file);
      }
    }
    _selectedFiles = kept;
    await _deduplicateSelectedFilesAndRepairPlaylists();
    _cleanupPlaylists();
    await _saveFiles();
    await _savePlaylists();
    notifyListeners();
  }

  Future<void> removeFile(File file) async {
    _selectedFiles.removeWhere((item) => item.path == file.path);
    _cleanupPlaylists();
    await _saveFiles();
    await _savePlaylists();
    notifyListeners();
  }

  Future<void> clearAllFiles() async {
    _selectedFiles.clear();
    _playlists.clear();
    await _saveFiles();
    await _savePlaylists();
    notifyListeners();
  }

  Future<String?> createPlaylist({
    required String name,
    required Set<String> trackPaths,
  }) async {
    final trimmedName = name.trim();
    final cleanedPaths = _validTrackPaths(trackPaths);

    if (trimmedName.isEmpty || cleanedPaths.isEmpty) {
      return null;
    }

    final id = 'pl_${DateTime.now().millisecondsSinceEpoch}';
    _playlists.add(
      LocalPlaylist(id: id, name: trimmedName, trackPaths: cleanedPaths),
    );
    await _savePlaylists();
    notifyListeners();
    return id;
  }

  Future<void> deletePlaylist(String playlistId) async {
    _playlists.removeWhere((item) => item.id == playlistId);
    await _savePlaylists();
    notifyListeners();
  }

  Future<bool> addTrackToPlaylist({
    required String playlistId,
    required String trackPath,
  }) async {
    final playlist = _playlists.cast<LocalPlaylist?>().firstWhere(
      (item) => item?.id == playlistId,
      orElse: () => null,
    );
    if (playlist == null) return false;

    final trackExists = _selectedFiles.any((file) => file.path == trackPath);
    if (!trackExists) return false;

    final changed = playlist.trackPaths.add(trackPath);
    if (!changed) return false;

    await _savePlaylists();
    notifyListeners();
    return true;
  }

  Future<bool> removeTrackFromPlaylist({
    required String playlistId,
    required String trackPath,
  }) async {
    final playlist = _playlists.cast<LocalPlaylist?>().firstWhere(
      (item) => item?.id == playlistId,
      orElse: () => null,
    );
    if (playlist == null) return false;

    final changed = playlist.trackPaths.remove(trackPath);
    if (!changed) return false;

    if (playlist.trackPaths.isEmpty) {
      _playlists.removeWhere((item) => item.id == playlistId);
    }

    await _savePlaylists();
    notifyListeners();
    return true;
  }

  List<File> getTracksForPlaylist(String playlistId) {
    if (playlistId == 'all') return _selectedFiles;

    final playlist = _playlists.firstWhere(
      (item) => item.id == playlistId,
      orElse: () => LocalPlaylist(id: 'all', name: '', trackPaths: {}),
    );

    if (playlist.id == 'all') return _selectedFiles;
    return _selectedFiles
        .where((file) => playlist.trackPaths.contains(file.path))
        .toList();
  }

  Set<String> _validTrackPaths(Set<String> rawPaths) {
    final existing = _selectedFiles.map((file) => file.path).toSet();
    return rawPaths.where(existing.contains).toSet();
  }

  void _cleanupPlaylists() {
    final existingPaths = _selectedFiles.map((file) => file.path).toSet();
    for (final playlist in _playlists) {
      playlist.trackPaths.removeWhere((path) => !existingPaths.contains(path));
    }
    _playlists.removeWhere((playlist) => playlist.trackPaths.isEmpty);
  }

  Future<void> _deduplicateSelectedFilesAndRepairPlaylists() async {
    final keyToKeptPath = <String, String>{};
    final duplicatePathToKeptPath = <String, String>{};
    final dedupedFiles = <File>[];

    for (final file in _selectedFiles) {
      final key = _fileDedupKey(file);
      final keptPath = keyToKeptPath[key];
      if (keptPath == null) {
        keyToKeptPath[key] = file.path;
        dedupedFiles.add(file);
      } else {
        duplicatePathToKeptPath[file.path] = keptPath;
      }
    }

    if (duplicatePathToKeptPath.isNotEmpty) {
      for (final playlist in _playlists) {
        final updated = <String>{};
        for (final path in playlist.trackPaths) {
          updated.add(duplicatePathToKeptPath[path] ?? path);
        }
        playlist.trackPaths
          ..clear()
          ..addAll(updated);
      }
    }

    _selectedFiles = dedupedFiles;
  }

  String _fileDedupKey(File file) {
    final base = p.basename(file.path).toLowerCase();
    int size = -1;
    try {
      size = file.lengthSync();
    } catch (_) {}
    return '$base|$size';
  }

  Future<void> _saveFiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filePaths = _selectedFiles.map((file) => file.path).toList();
      await prefs.setString(_filesKey, json.encode(filePaths));
    } catch (_) {}
  }

  Future<void> _savePlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _playlists.map((item) => item.toJson()).toList();
      await prefs.setString(_playlistsKey, json.encode(data));
    } catch (_) {}
  }
}
