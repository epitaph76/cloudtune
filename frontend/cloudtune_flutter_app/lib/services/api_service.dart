import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../utils/constants.dart';

class ApiService {
  final Dio _dio;
  late final List<String> _baseUrls;

  ApiService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      ) {
    _baseUrls = {
      Constants.primaryBaseUrl,
      ...Constants.fallbackBaseUrls,
    }.toList();
  }

  bool _isNetworkDioError(Object error) {
    if (error is! DioException) return false;
    final responseMissing = error.response == null;
    final connectionError = error.type == DioExceptionType.connectionError;
    final failedHostLookup =
        error.error is SocketException ||
        error.message.toString().contains('Failed host lookup');
    return responseMissing && (connectionError || failedHostLookup);
  }

  Future<Response<T>> _requestWithFallback<T>({
    required String method,
    required String path,
    Object? data,
    Options? options,
  }) async {
    Object? lastError;
    for (var i = 0; i < _baseUrls.length; i++) {
      final url = '${_baseUrls[i]}$path';
      try {
        return await _dio.request<T>(
          url,
          data: data,
          options: (options ?? Options()).copyWith(method: method),
        );
      } catch (error) {
        lastError = error;
        final canTryNext = i < _baseUrls.length - 1;
        if (!canTryNext || !_isNetworkDioError(error)) {
          rethrow;
        }
      }
    }
    throw lastError ?? Exception('Request failed');
  }

  // Метод для получения токена из SharedPreferences
  Future<String?> _getToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(Constants.tokenKey);
  }

  // Добавляем токен авторизации к запросу
  Future<Options> _getAuthOptions() async {
    String? token = await _getToken();
    if (token != null) {
      return Options(headers: {'Authorization': 'Bearer $token'});
    }
    throw Exception('Пользователь не авторизован');
  }

  // Загрузка файла на сервер
  Future<Map<String, dynamic>> uploadFile(File file) async {
    try {
      Options options = await _getAuthOptions();

      String fileName = file.path.split('/').last;

      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
      });

      Response response = await _requestWithFallback(
        method: 'POST',
        path: '/api/songs/upload',
        data: formData,
        options: options,
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': response.data};
      } else {
        return {'success': false, 'message': 'Ошибка при загрузке файла'};
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // Получение библиотеки песен пользователя
  Future<Map<String, dynamic>> getUserLibrary() async {
    try {
      Options options = await _getAuthOptions();

      Response response = await _requestWithFallback(
        method: 'GET',
        path: '/api/songs/library',
        options: options,
      );

      if (response.statusCode == 200) {
        return {'success': true, 'songs': response.data['songs']};
      } else {
        return {'success': false, 'message': 'Ошибка при получении библиотеки'};
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // Получение плейлистов пользователя
  Future<Map<String, dynamic>> getUserPlaylists() async {
    try {
      Options options = await _getAuthOptions();

      Response response = await _requestWithFallback(
        method: 'GET',
        path: '/api/playlists',
        options: options,
      );

      if (response.statusCode == 200) {
        final playlistsRaw = response.data['playlists'];
        return {
          'success': true,
          'playlists': playlistsRaw is List ? playlistsRaw : <dynamic>[],
        };
      } else {
        return {'success': false, 'message': 'Ошибка при получении плейлистов'};
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> createPlaylist({
    required String name,
    String? description,
    bool isPublic = false,
  }) async {
    try {
      final options = await _getAuthOptions();
      final response = await _requestWithFallback(
        method: 'POST',
        path: '/api/playlists',
        data: {'name': name, 'description': description, 'is_public': isPublic},
        options: options,
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'playlist_id': response.data['playlist_id'],
          'playlist': response.data['playlist'],
        };
      }
      return {'success': false, 'message': 'Failed to create playlist'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
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
    } catch (e) {
      return {'success': false, 'message': e.toString()};
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

      if (response.statusCode == 200) {
        return {
          'success': true,
          'songs': response.data['songs'] ?? <dynamic>[],
          'count': response.data['count'] ?? 0,
        };
      }
      return {'success': false, 'message': 'Failed to fetch playlist songs'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
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
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // Скачивание файла с сервера
  Future<Map<String, dynamic>> downloadFile(int fileId, String savePath) async {
    try {
      Options options = await _getAuthOptions();

      // Создаем файл для сохранения
      File file = File(savePath);

      // Открываем поток для записи
      RandomAccessFile randomAccessFile = await file.open(mode: FileMode.write);

      try {
        // Выполняем запрос с потоковой передачей
        Response<ResponseBody> response =
            await _requestWithFallback<ResponseBody>(
              method: 'GET',
              path: '/api/songs/download/$fileId',
              options: options.copyWith(responseType: ResponseType.stream),
            );

        if (response.statusCode == 200) {
          // Получаем поток данных
          Stream<List<int>> stream = response.data!.stream;

          // Читаем поток по кусочкам и записываем в файл
          await for (List<int> chunk in stream) {
            await randomAccessFile.writeFrom(chunk);
          }

          return {'success': true, 'filePath': file.path};
        } else {
          return {
            'success': false,
            'message': 'Ошибка при скачивании файла: ${response.statusCode}',
          };
        }
      } finally {
        // Закрываем файл
        await randomAccessFile.close();
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
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

      if (response.statusCode == 200) {
        return {
          'success': true,
          'used_bytes': response.data['used_bytes'] ?? 0,
          'quota_bytes': response.data['quota_bytes'] ?? 0,
          'remaining_bytes': response.data['remaining_bytes'] ?? 0,
        };
      }

      return {
        'success': false,
        'message': 'Ошибка при получении квоты хранилища',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
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
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
