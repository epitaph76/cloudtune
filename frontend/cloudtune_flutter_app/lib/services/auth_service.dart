import '../models/user.dart';
import 'backend_client.dart';
import 'session_storage_service.dart';

class AuthService {
  AuthService({
    BackendClient? backendClient,
    SessionStorageService? sessionStorage,
  }) : _backendClient =
           backendClient ??
           BackendClient(
             connectTimeout: const Duration(seconds: 9),
             receiveTimeout: const Duration(seconds: 9),
           ),
       _sessionStorage = sessionStorage ?? SessionStorageService();

  final BackendClient _backendClient;
  final SessionStorageService _sessionStorage;

  Future<Map<String, dynamic>> register(
    String email,
    String username,
    String password,
  ) async {
    try {
      final response = await _backendClient.request<dynamic>(
        method: 'POST',
        path: '/auth/register',
        data: {'email': email, 'username': username, 'password': password},
      );

      if (response.statusCode != 200 ||
          response.data is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Registration failed'};
      }

      final data = response.data as Map<String, dynamic>;
      final userJson = data['user'];
      final token = data['token']?.toString() ?? '';
      if (userJson is! Map<String, dynamic> || token.isEmpty) {
        return {'success': false, 'message': 'Registration failed'};
      }

      final user = User.fromJson(userJson);
      await _sessionStorage.saveToken(token);
      await _sessionStorage.cacheUser(user);

      return {
        'success': true,
        'user': user,
        'token': token,
        'message': data['message'],
      };
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Registration failed',
        ),
      };
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _backendClient.request<dynamic>(
        method: 'POST',
        path: '/auth/login',
        data: {'email': email, 'password': password},
      );

      if (response.statusCode != 200 ||
          response.data is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Login failed'};
      }

      final data = response.data as Map<String, dynamic>;
      final userJson = data['user'];
      final token = data['token']?.toString() ?? '';
      if (userJson is! Map<String, dynamic> || token.isEmpty) {
        return {'success': false, 'message': 'Login failed'};
      }

      final user = User.fromJson(userJson);
      await _sessionStorage.saveToken(token);
      await _sessionStorage.cacheUser(user);

      return {
        'success': true,
        'user': user,
        'token': token,
        'message': data['message'],
      };
    } catch (error) {
      return {
        'success': false,
        'message': _backendClient.describeError(
          error,
          fallbackMessage: 'Login failed',
        ),
      };
    }
  }

  Future<bool> isLoggedIn() async {
    final token = await _sessionStorage.readToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    await _sessionStorage.clearToken();
    await _sessionStorage.clearCachedUser();
  }

  Future<String?> getToken() => _sessionStorage.readToken();

  Future<User?> getCachedUser() => _sessionStorage.getCachedUser();

  Future<void> cacheUser(User user) => _sessionStorage.cacheUser(user);
}
