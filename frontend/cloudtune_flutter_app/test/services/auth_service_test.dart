import 'dart:io';

import 'package:cloudtune_flutter_app/models/user.dart';
import 'package:cloudtune_flutter_app/services/auth_service.dart';
import 'package:cloudtune_flutter_app/services/backend_client.dart';
import 'package:cloudtune_flutter_app/services/session_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBackendClient extends BackendClient {
  _FakeBackendClient({this.responseStatusCode = 200, this.throwError});

  int responseStatusCode;
  Object? throwError;
  String? lastPath;
  String? lastMethod;
  Options? lastOptions;

  @override
  Future<Response<T>> request<T>({
    required String method,
    required String path,
    Object? data,
    Options? options,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    lastPath = path;
    lastMethod = method;
    lastOptions = options;

    if (throwError != null) {
      throw throwError!;
    }

    return Response<T>(
      requestOptions: RequestOptions(path: path, method: method),
      statusCode: responseStatusCode,
    );
  }
}

class _FakeSessionStorageService extends SessionStorageService {
  _FakeSessionStorageService({this.token, this.cachedUser});

  String? token;
  User? cachedUser;
  int clearTokenCalls = 0;
  int clearCachedUserCalls = 0;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String token) async {
    this.token = token;
  }

  @override
  Future<void> clearToken() async {
    clearTokenCalls += 1;
    token = null;
  }

  @override
  Future<User?> getCachedUser() async => cachedUser;

  @override
  Future<void> cacheUser(User user) async {
    cachedUser = user;
  }

  @override
  Future<void> clearCachedUser() async {
    clearCachedUserCalls += 1;
    cachedUser = null;
  }
}

void main() {
  test('isLoggedIn returns false when token is missing', () async {
    final backendClient = _FakeBackendClient();
    final sessionStorage = _FakeSessionStorageService(token: null);
    final authService = AuthService(
      backendClient: backendClient,
      sessionStorage: sessionStorage,
    );

    final isLoggedIn = await authService.isLoggedIn();

    expect(isLoggedIn, isFalse);
    expect(backendClient.lastPath, isNull);
    expect(sessionStorage.clearTokenCalls, 0);
    expect(sessionStorage.clearCachedUserCalls, 0);
  });

  test('isLoggedIn validates token via protected probe endpoint', () async {
    final backendClient = _FakeBackendClient(responseStatusCode: 200);
    final sessionStorage = _FakeSessionStorageService(token: 'valid-token');
    final authService = AuthService(
      backendClient: backendClient,
      sessionStorage: sessionStorage,
    );

    final isLoggedIn = await authService.isLoggedIn();

    expect(isLoggedIn, isTrue);
    expect(backendClient.lastMethod, 'GET');
    expect(backendClient.lastPath, '/api/storage/usage');
    expect(
      backendClient.lastOptions?.headers?['Authorization'],
      'Bearer valid-token',
    );
    expect(sessionStorage.clearTokenCalls, 0);
    expect(sessionStorage.clearCachedUserCalls, 0);
  });

  test(
    'isLoggedIn clears local session when probe returns unauthorized',
    () async {
      final backendClient = _FakeBackendClient(
        throwError: DioException(
          requestOptions: RequestOptions(path: '/api/storage/usage'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/storage/usage'),
            statusCode: 401,
            data: <String, dynamic>{'error': 'Invalid token'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      final sessionStorage = _FakeSessionStorageService(
        token: 'expired-token',
        cachedUser: User(id: '42', email: 'test@example.com', username: 'test'),
      );
      final authService = AuthService(
        backendClient: backendClient,
        sessionStorage: sessionStorage,
      );

      final isLoggedIn = await authService.isLoggedIn();

      expect(isLoggedIn, isFalse);
      expect(sessionStorage.clearTokenCalls, 1);
      expect(sessionStorage.clearCachedUserCalls, 1);
      expect(sessionStorage.token, isNull);
      expect(sessionStorage.cachedUser, isNull);
    },
  );

  test(
    'isLoggedIn returns false on network error without clearing local session',
    () async {
      final backendClient = _FakeBackendClient(
        throwError: DioException(
          requestOptions: RequestOptions(path: '/api/storage/usage'),
          type: DioExceptionType.connectionError,
          error: const SocketException('offline'),
        ),
      );
      final sessionStorage = _FakeSessionStorageService(
        token: 'valid-token',
        cachedUser: User(
          id: '7',
          email: 'offline@example.com',
          username: 'offline',
        ),
      );
      final authService = AuthService(
        backendClient: backendClient,
        sessionStorage: sessionStorage,
      );

      final isLoggedIn = await authService.isLoggedIn();

      expect(isLoggedIn, isFalse);
      expect(sessionStorage.clearTokenCalls, 0);
      expect(sessionStorage.clearCachedUserCalls, 0);
      expect(sessionStorage.token, 'valid-token');
      expect(sessionStorage.cachedUser?.id, '7');
    },
  );
}
