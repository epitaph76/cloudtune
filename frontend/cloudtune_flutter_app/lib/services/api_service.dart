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
  static const int _uploadMaxAttempts = 2;
  static const List<Duration> _uploadRetryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];
  static const Duration _uploadReceiveTimeout = Duration(minutes: 5);

  Future<Response<T>> _requestWithFallback<T>({
    required String method,
    required String path,
    Object? data,
    Options? options,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) {
    return _backendClient.request<T>(
      method: method,
      path: path,
      data: data,
      options: options,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
    );
  }

  Map<String, dynamic> _mapOrEmpty(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  List<int> _asIntList(Object? raw) {
    if (raw is! List) return const <int>[];

    final out = <int>[];
    for (final item in raw) {
      final parsed = _asInt(item);
      if (parsed == null) continue;
      out.add(parsed);
    }
    return out;
  }

  String _extractApiMessage(Object? raw, {required String fallback}) {
    if (raw is Map<String, dynamic>) {
      final apiError = raw['error'];
      if (apiError is String && apiError.trim().isNotEmpty) {
        return apiError.trim();
      }

      final apiMessage = raw['message'];
      if (apiMessage is String && apiMessage.trim().isNotEmpty) {
        return apiMessage.trim();
      }
    }
    if (raw is Map) {
      return _extractApiMessage(
        Map<String, dynamic>.from(raw),
        fallback: fallback,
      );
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return fallback;
  }

  int? _extractSongIdFromUploadResponse(Map<String, dynamic> data) {
    final topLevelSongId = _asInt(data['song_id']);
    if (topLevelSongId != null && topLevelSongId > 0) {
      return topLevelSongId;
    }

    final nestedSongId = _asInt(_mapOrEmpty(data['song'])['id']);
    if (nestedSongId != null && nestedSongId > 0) {
      return nestedSongId;
    }

    return null;
  }

  bool _isRetriableUploadStatusCode(int? statusCode) {
    if (statusCode == null) return false;
    if (statusCode == 408 || statusCode == 429) return true;
    return statusCode >= 500 && statusCode <= 599;
  }

  bool _isRetriableUploadException(Object error) {
    if (error is! DioException) return false;
    if (_isRetriableUploadStatusCode(error.response?.statusCode)) {
      return true;
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.sendTimeout:
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
        return false;
    }
  }

  Duration _uploadRetryDelayForAttempt(int attempt) {
    final index = attempt - 1;
    if (index <= 0) return _uploadRetryDelays.first;
    if (index >= _uploadRetryDelays.length) return _uploadRetryDelays.last;
    return _uploadRetryDelays[index];
  }

  Future<Options> _getAuthOptions() async {
    final token = await _sessionStorage.readToken();
    if (token != null && token.isNotEmpty) {
      return Options(headers: {'Authorization': 'Bearer $token'});
    }
    throw StateError('User is not authenticated');
  }

  Future<bool> _verifySongExistsInLibrary({
    required int songId,
    required Options options,
  }) async {
    final response = await _requestWithFallback(
      method: 'GET',
      path: '/api/songs/$songId',
      options: options,
    );
    return response.statusCode == 200;
  }

  Future<Map<String, dynamic>> uploadFile(
    File file, {
    CancelToken? cancelToken,
  }) async {
    final options = await _getAuthOptions();
    final fileName = p.basename(file.path);

    for (var attempt = 1; attempt <= _uploadMaxAttempts; attempt++) {
      if (cancelToken?.isCancelled == true) {
        return {
          'success': false,
          'canceled': true,
          'message': 'Upload canceled',
        };
      }
      final isLastAttempt = attempt >= _uploadMaxAttempts;
      try {
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path, filename: fileName),
        });
        final uploadOptions = options.copyWith(
          receiveTimeout: _uploadReceiveTimeout,
        );
        final response = await _requestWithFallback(
          method: 'POST',
          path: '/api/songs/upload',
          data: formData,
          options: uploadOptions,
          cancelToken: cancelToken,
        );

        final statusCode = response.statusCode ?? -1;
        final data = _mapOrEmpty(response.data);
        if (statusCode != 200) {
          if (!isLastAttempt && _isRetriableUploadStatusCode(statusCode)) {
            await Future<void>.delayed(_uploadRetryDelayForAttempt(attempt));
            continue;
          }
          return {
            'success': false,
            'status_code': statusCode,
            'message': _extractApiMessage(
              response.data,
              fallback: 'Upload failed (HTTP $statusCode)',
            ),
          };
        }

        final songId = _extractSongIdFromUploadResponse(data);
        if (songId == null) {
          return {
            'success': false,
            'status_code': statusCode,
            'message':
                'Upload failed: backend response does not include valid song_id',
            'data': data,
          };
        }

        final existsInLibrary = await _verifySongExistsInLibrary(
          songId: songId,
          options: options,
        );
        if (!existsInLibrary) {
          return {
            'success': false,
            'song_id': songId,
            'message':
                'Upload failed: song_id=$songId is not visible in cloud library after upload',
            'data': data,
          };
        }

        return {'success': true, 'song_id': songId, 'data': data};
      } catch (error) {
        if (error is DioException && error.type == DioExceptionType.cancel) {
          return {
            'success': false,
            'canceled': true,
            'message': 'Upload canceled',
          };
        }
        final statusCode = error is DioException
            ? error.response?.statusCode
            : null;
        final message = _backendClient.describeError(
          error,
          fallbackMessage: 'Upload failed',
        );

        if (!isLastAttempt && _isRetriableUploadException(error)) {
          await Future<void>.delayed(_uploadRetryDelayForAttempt(attempt));
          continue;
        }

        return {
          'success': false,
          'status_code': statusCode,
          'message': message,
        };
      }
    }

    return {'success': false, 'message': 'Upload failed'};
  }

  Future<Map<String, dynamic>> getUserLibrary({
    int limit = 50,
    int offset = 0,
    String search = '',
  }) async {
    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'GET',
        path: '/api/songs/library',
        options: options,
        queryParameters: {
          'limit': limit,
          'offset': offset,
          if (search.trim().isNotEmpty) 'search': search.trim(),
        },
      );

      final data = _mapOrEmpty(response.data);
      if (response.statusCode == 200) {
        final songs = data['songs'];
        return {
          'success': true,
          'songs': songs is List ? songs : <dynamic>[],
          'count': _asInt(data['count']) ?? 0,
          'total': _asInt(data['total']) ?? 0,
          'limit': _asInt(data['limit']) ?? limit,
          'offset': _asInt(data['offset']) ?? offset,
          'has_more': data['has_more'] == true,
          'next_offset': _asInt(data['next_offset']) ?? -1,
          'search': (data['search'] as String?) ?? search,
        };
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

  Future<Map<String, dynamic>> getUserPlaylists({
    int limit = 50,
    int offset = 0,
    String search = '',
  }) async {
    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'GET',
        path: '/api/playlists',
        options: options,
        queryParameters: {
          'limit': limit,
          'offset': offset,
          if (search.trim().isNotEmpty) 'search': search.trim(),
        },
      );

      final data = _mapOrEmpty(response.data);
      if (response.statusCode == 200) {
        final playlistsRaw = data['playlists'];
        return {
          'success': true,
          'playlists': playlistsRaw is List ? playlistsRaw : <dynamic>[],
          'count': _asInt(data['count']) ?? 0,
          'total': _asInt(data['total']) ?? 0,
          'limit': _asInt(data['limit']) ?? limit,
          'offset': _asInt(data['offset']) ?? offset,
          'has_more': data['has_more'] == true,
          'next_offset': _asInt(data['next_offset']) ?? -1,
          'search': (data['search'] as String?) ?? search,
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
      return {'success': false, 'message': 'No valid songs to add'};
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
          'added_song_ids': _asIntList(data['added_song_ids']),
          'skipped_existing_song_ids': _asIntList(
            data['skipped_existing_song_ids'],
          ),
          'skipped_not_in_library_song_ids': _asIntList(
            data['skipped_not_in_library_song_ids'],
          ),
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

  Future<Map<String, dynamic>> getPlaylistSongs(
    int playlistId, {
    int limit = 50,
    int offset = 0,
    String search = '',
  }) async {
    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'GET',
        path: '/api/playlists/$playlistId/songs',
        options: options,
        queryParameters: {
          'limit': limit,
          'offset': offset,
          if (search.trim().isNotEmpty) 'search': search.trim(),
        },
      );

      final data = _mapOrEmpty(response.data);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'songs': data['songs'] is List ? data['songs'] : <dynamic>[],
          'count': _asInt(data['count']) ?? 0,
          'total': _asInt(data['total']) ?? 0,
          'limit': _asInt(data['limit']) ?? limit,
          'offset': _asInt(data['offset']) ?? offset,
          'has_more': data['has_more'] == true,
          'next_offset': _asInt(data['next_offset']) ?? -1,
          'search': (data['search'] as String?) ?? search,
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

  Future<Map<String, dynamic>> downloadFile(
    int fileId,
    String savePath, {
    CancelToken? cancelToken,
  }) async {
    final file = File(savePath);
    RandomAccessFile? randomAccessFile;
    var canceled = false;

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
        cancelToken: cancelToken,
      );

      if (response.statusCode != 200 || response.data == null) {
        return {
          'success': false,
          'message': 'Download failed: ${response.statusCode}',
        };
      }

      await for (final chunk in response.data!.stream) {
        if (cancelToken?.isCancelled == true) {
          canceled = true;
          return {
            'success': false,
            'canceled': true,
            'message': 'Download canceled',
          };
        }
        await randomAccessFile.writeFrom(chunk);
      }

      return {'success': true, 'filePath': file.path};
    } catch (error) {
      if (error is DioException && error.type == DioExceptionType.cancel) {
        canceled = true;
        return {
          'success': false,
          'canceled': true,
          'message': 'Download canceled',
        };
      }
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Download failed',
        ),
      };
    } finally {
      await randomAccessFile?.close();
      if (canceled && await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
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
