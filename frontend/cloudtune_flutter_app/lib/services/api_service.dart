import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'backend_client.dart';
import 'session_storage_service.dart';

class ApiService {
  ApiService({
    BackendClient? backendClient,
    SessionStorageService? sessionStorage,
  }) : _backendClient = backendClient ?? BackendClient(),
       _sessionStorage = sessionStorage ?? SessionStorageService();

  final BackendClient _backendClient;
  final SessionStorageService _sessionStorage;

  Future<Response<T>> _requestWithFallback<T>({
    required String method,
    required String path,
    Object? data,
    Options? options,
    Map<String, dynamic>? queryParameters,
  }) {
    return _backendClient.request<T>(
      method: method,
      path: path,
      data: data,
      options: options,
      queryParameters: queryParameters,
    );
  }

  Map<String, dynamic> _mapOrEmpty(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Future<Options> _getAuthOptions() async {
    final token = await _sessionStorage.readToken();
    if (token != null && token.isNotEmpty) {
      return Options(headers: {'Authorization': 'Bearer $token'});
    }
    throw StateError('User is not authenticated');
  }

  Future<Map<String, dynamic>> uploadFile(File file) async {
    try {
      final options = await _getAuthOptions();
      final fileName = p.basename(file.path);
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
      });

      final response = await _requestWithFallback(
        method: 'POST',
        path: '/api/songs/upload',
        data: formData,
        options: options,
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': response.data};
      }

      return {'success': false, 'message': 'Ошибка при загрузке файла'};
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Ошибка при загрузке файла',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> getUserLibrary() async {
    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'GET',
        path: '/api/songs/library',
        options: options,
      );

      final data = _mapOrEmpty(response.data);
      if (response.statusCode == 200) {
        final songs = data['songs'];
        return {'success': true, 'songs': songs is List ? songs : <dynamic>[]};
      }

      return {'success': false, 'message': 'Ошибка при получении библиотеки'};
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Ошибка при получении библиотеки',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> getUserPlaylists() async {
    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'GET',
        path: '/api/playlists',
        options: options,
      );

      final data = _mapOrEmpty(response.data);
      if (response.statusCode == 200) {
        final playlistsRaw = data['playlists'];
        return {
          'success': true,
          'playlists': playlistsRaw is List ? playlistsRaw : <dynamic>[],
        };
      }

      return {'success': false, 'message': 'Ошибка при получении плейлистов'};
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Ошибка при получении плейлистов',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> createPlaylist({
    required String name,
    String? description,
    bool isPublic = false,
    bool isFavorite = false,
    bool replaceExisting = false,
  }) async {
    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'POST',
        path: '/api/playlists',
        data: {
          'name': name,
          'description': description,
          'is_public': isPublic,
          'is_favorite': isFavorite,
          'replace_existing': replaceExisting,
        },
        options: options,
      );

      final data = _mapOrEmpty(response.data);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'playlist_id': data['playlist_id'],
          'playlist': data['playlist'],
        };
      }

      return {'success': false, 'message': 'Failed to create playlist'};
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Failed to create playlist',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> addSongToPlaylist({
    required int playlistId,
    required int songId,
  }) async {
    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'POST',
        path: '/api/playlists/$playlistId/songs/$songId',
        options: options,
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': response.data};
      }

      return {'success': false, 'message': 'Failed to add song to playlist'};
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Failed to add song to playlist',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> addSongsToPlaylistBulk({
    required int playlistId,
    required List<int> songIds,
  }) async {
    final normalized = <int>[];
    final seen = <int>{};
    for (final id in songIds) {
      if (id <= 0 || !seen.add(id)) continue;
      normalized.add(id);
    }
    if (normalized.isEmpty) {
      return {
        'success': false,
        'message': 'No valid songs to add',
      };
    }

    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'POST',
        path: '/api/playlists/$playlistId/songs/bulk',
        data: {'song_ids': normalized},
        options: options,
      );

      final data = _mapOrEmpty(response.data);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'added_count': data['added_count'] ?? 0,
          'skipped_existing': data['skipped_existing'] ?? 0,
          'skipped_not_in_library': data['skipped_not_in_library'] ?? 0,
          'data': data,
        };
      }

      return {'success': false, 'message': 'Failed to add songs to playlist'};
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Failed to add songs to playlist',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> getPlaylistSongs(int playlistId) async {
    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'GET',
        path: '/api/playlists/$playlistId/songs',
        options: options,
      );

      final data = _mapOrEmpty(response.data);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'songs': data['songs'] is List ? data['songs'] : <dynamic>[],
          'count': data['count'] is num ? (data['count'] as num).toInt() : 0,
        };
      }

      return {'success': false, 'message': 'Failed to fetch playlist songs'};
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Failed to fetch playlist songs',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> deletePlaylist(int playlistId) async {
    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'DELETE',
        path: '/api/playlists/$playlistId',
        options: options,
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': response.data};
      }

      return {'success': false, 'message': 'Failed to delete playlist'};
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Failed to delete playlist',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> downloadFile(int fileId, String savePath) async {
    final file = File(savePath);
    RandomAccessFile? randomAccessFile;

    try {
      final options = await _getAuthOptions();
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      randomAccessFile = await file.open(mode: FileMode.write);

      final response = await _requestWithFallback<ResponseBody>(
        method: 'GET',
        path: '/api/songs/download/$fileId',
        options: options.copyWith(responseType: ResponseType.stream),
      );

      if (response.statusCode != 200 || response.data == null) {
        return {
          'success': false,
          'message': 'Ошибка при скачивании файла: ${response.statusCode}',
        };
      }

      await for (final chunk in response.data!.stream) {
        await randomAccessFile.writeFrom(chunk);
      }

      return {'success': true, 'filePath': file.path};
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Ошибка при скачивании файла',
        ),
      };
    } finally {
      await randomAccessFile?.close();
    }
  }

  Future<Map<String, dynamic>> getStorageUsage() async {
    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'GET',
        path: '/api/storage/usage',
        options: options,
      );

      final data = _mapOrEmpty(response.data);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'used_bytes': data['used_bytes'] ?? 0,
          'quota_bytes': data['quota_bytes'] ?? 0,
          'remaining_bytes': data['remaining_bytes'] ?? 0,
        };
      }

      return {
        'success': false,
        'message': 'Ошибка при получении квоты хранилища',
      };
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Ошибка при получении квоты хранилища',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> deleteSong(int songId) async {
    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'DELETE',
        path: '/api/songs/$songId',
        options: options,
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': response.data};
      }

      return {'success': false, 'message': 'Failed to delete song'};
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Failed to delete song',
        ),
      };
    }
  }
}
