import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../utils/constants.dart';

class AuthService {
  final Dio _dio = Dio();

  String get baseUrl => Constants.baseUrl;

  Future<Map<String, dynamic>> register(String email, String username, String password) async {
    try {
      final response = await _dio.post(
        '$baseUrl/auth/register',
        data: {
          'email': email,
          'username': username,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final user = User.fromJson(data['user']);
        final token = data['token'];

        // Save token to shared preferences
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString(Constants.tokenKey, token);

        return {
          'success': true,
          'user': user,
          'token': token,
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'message': 'Registration failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _dio.post(
        '$baseUrl/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final user = User.fromJson(data['user']);
        final token = data['token'];

        // Save token to shared preferences
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString(Constants.tokenKey, token);

        return {
          'success': true,
          'user': user,
          'token': token,
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'message': 'Login failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  Future<bool> isLoggedIn() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(Constants.tokenKey) != null;
  }

  Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(Constants.tokenKey);
  }

  Future<String?> getToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(Constants.tokenKey);
  }
}