import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class LocalMusicProvider with ChangeNotifier {
  List<File> _selectedFiles = [];
  static const String _filesKey = 'selected_audio_files';

  LocalMusicProvider() {
    _loadSavedFiles();
  }

  List<File> get selectedFiles => _selectedFiles;

  Future<void> _loadSavedFiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filesJson = prefs.getString(_filesKey);
      
      if (filesJson != null) {
        final List<String> filePaths = List<String>.from(json.decode(filesJson));
        
        // Filter out files that no longer exist
        _selectedFiles = [];
        for (String path in filePaths) {
          final file = File(path);
          if (await file.exists()) {
            _selectedFiles.add(file);
          }
        }
        
        notifyListeners();
      }
    } catch (e) {
      // Log error in production
    }
  }

  Future<void> addFiles(List<File> files) async {
    _selectedFiles.addAll(files);
    await _saveFiles();
    notifyListeners();
  }

  Future<void> removeFile(File file) async {
    _selectedFiles.remove(file);
    await _saveFiles();
    notifyListeners();
  }

  Future<void> clearAllFiles() async {
    _selectedFiles.clear();
    await _saveFiles();
    notifyListeners();
  }

  Future<void> _saveFiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filePaths = _selectedFiles.map((file) => file.path).toList();
      await prefs.setString(_filesKey, json.encode(filePaths));
    } catch (e) {
      // Log error in production
    }
  }

  int get fileCount => _selectedFiles.length;
}