import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../utils/constants.dart';

class ApiService {
  final Dio _dio;

  ApiService() : _dio = Dio(BaseOptions(
    baseUrl: Constants.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

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

      Response response = await _dio.post(
        '/api/songs/upload',
        data: formData,
        options: options,
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': response.data,
        };
      } else {
        return {
          'success': false,
          'message': 'Ошибка при загрузке файла',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  // Получение библиотеки песен пользователя
  Future<Map<String, dynamic>> getUserLibrary() async {
    try {
      Options options = await _getAuthOptions();
      
      Response response = await _dio.get('/api/songs/library', options: options);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'songs': response.data['songs'],
        };
      } else {
        return {
          'success': false,
          'message': 'Ошибка при получении библиотеки',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  // Получение плейлистов пользователя
  Future<Map<String, dynamic>> getUserPlaylists() async {
    try {
      Options options = await _getAuthOptions();
      
      Response response = await _dio.get('/api/playlists', options: options);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'playlists': response.data['playlists'],
        };
      } else {
        return {
          'success': false,
          'message': 'Ошибка при получении плейлистов',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(),
      };
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
        Response<ResponseBody> response = await _dio.get<ResponseBody>(
          '/api/songs/download/$fileId',
          options: options.copyWith(
            responseType: ResponseType.stream,
          ),
        );

        if (response.statusCode == 200) {
          // Получаем поток данных
          Stream<List<int>> stream = response.data!.stream;
          
          // Читаем поток по кусочкам и записываем в файл
          await for (List<int> chunk in stream) {
            await randomAccessFile.writeFrom(chunk);
          }
          
          return {
            'success': true,
            'filePath': file.path,
          };
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
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }
}