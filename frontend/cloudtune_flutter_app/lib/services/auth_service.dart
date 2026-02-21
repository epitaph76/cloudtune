import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import '../models/user.dart';
import '../utils/constants.dart';

class AuthService {
  final Dio _dio;
  late final List<String> _baseUrls;

  AuthService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 9),
          receiveTimeout: const Duration(seconds: 9),
        ),
      ) {
    _baseUrls = <String>[
      Constants.primaryBaseUrl,
      ...Constants.fallbackBaseUrls,
    ].toSet().toList();
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

  Future<Response<dynamic>> _postWithFallback(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    Object? lastError;
    for (var i = 0; i < _baseUrls.length; i++) {
      final url = '${_baseUrls[i]}$path';
      try {
        return await _dio.post(url, data: data);
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

  Future<Map<String, dynamic>> register(
    String email,
    String username,
    String password,
  ) async {
    try {
      final response = await _postWithFallback(
        '/auth/register',
        data: {'email': email, 'username': username, 'password': password},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final user = User.fromJson(data['user']);
        final token = data['token'];

        // Save token to shared preferences
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString(Constants.tokenKey, token);

        // Cache user details
        await prefs.setString(
          Constants.userCacheKey,
          json.encode(user.toJson()),
        );

        return {
          'success': true,
          'user': user,
          'token': token,
          'message': data['message'],
        };
      } else {
        return {'success': false, 'message': 'Registration failed'};
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _postWithFallback(
        '/auth/login',
        data: {'email': email, 'password': password},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final user = User.fromJson(data['user']);
        final token = data['token'];

        // Save token to shared preferences
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString(Constants.tokenKey, token);

        // Cache user details
        await prefs.setString(
          Constants.userCacheKey,
          json.encode(user.toJson()),
        );

        return {
          'success': true,
          'user': user,
          'token': token,
          'message': data['message'],
        };
      } else {
        return {'success': false, 'message': 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<bool> isLoggedIn() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString(Constants.tokenKey);
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(Constants.tokenKey);
    await prefs.remove(Constants.userCacheKey);
  }

  Future<String?> getToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(Constants.tokenKey);
  }

  // Method to get user details from stored token
  Future<User?> getCachedUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? userData = prefs.getString(Constants.userCacheKey);

    if (userData != null) {
      try {
        Map<String, dynamic> userMap = json.decode(userData);
        return User.fromJson(userMap);
      } catch (e) {
        // Log error in production
        return null;
      }
    }
    return null;
  }

  // Method to cache user details
  Future<void> cacheUser(User user) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(Constants.userCacheKey, json.encode(user.toJson()));
  }
}
