import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../utils/constants.dart';

class BackendClient {
  BackendClient({
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) : _dio = Dio(
         BaseOptions(
           connectTimeout: connectTimeout,
           receiveTimeout: receiveTimeout,
         ),
       ) {
    _baseUrls = {
      _normalizeBaseUrl(Constants.primaryBaseUrl),
      ...Constants.fallbackBaseUrls.map(_normalizeBaseUrl),
    }.where((url) => url.isNotEmpty).toList(growable: false);
  }

  final Dio _dio;
  late final List<String> _baseUrls;

  List<String> get activeBaseUrls => List<String>.unmodifiable(_baseUrls);

  static String _normalizeBaseUrl(String rawUrl) {
    return rawUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  bool _isNetworkDioError(Object error) {
    if (error is! DioException) return false;

    final responseMissing = error.response == null;
    final connectionError = error.type == DioExceptionType.connectionError;
    final connectionTimeout = error.type == DioExceptionType.connectionTimeout;
    final failedHostLookup =
        error.error is SocketException ||
        error.message.toString().contains('Failed host lookup');

    return responseMissing &&
        (connectionError || connectionTimeout || failedHostLookup);
  }

  String _hostLabel(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return url;
    }
    final portLabel = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$portLabel';
  }

  void _logRequestAttempt({
    required String method,
    required String url,
    required int attempt,
    required int totalAttempts,
  }) {
    final normalizedMethod = method.trim().toUpperCase();
    debugPrint(
      '[BackendClient] -> $normalizedMethod ${_hostLabel(url)} '
      '(attempt $attempt/$totalAttempts)',
    );
  }

  void _logResponse({
    required String method,
    required String url,
    required Response<dynamic> response,
  }) {
    final normalizedMethod = method.trim().toUpperCase();
    debugPrint(
      '[BackendClient] <- $normalizedMethod ${_hostLabel(url)} '
      'status=${response.statusCode ?? -1}',
    );
  }

  void _logFailure({
    required String method,
    required String url,
    required Object error,
    required bool willRetry,
  }) {
    final normalizedMethod = method.trim().toUpperCase();
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final suffix = willRetry ? ' (retrying next host)' : '';
      if (statusCode != null) {
        debugPrint(
          '[BackendClient] xx $normalizedMethod ${_hostLabel(url)} '
          'status=$statusCode$suffix',
        );
        return;
      }
      debugPrint(
        '[BackendClient] xx $normalizedMethod ${_hostLabel(url)} '
        'error=${error.type}$suffix',
      );
      return;
    }

    final suffix = willRetry ? ' (retrying next host)' : '';
    debugPrint(
      '[BackendClient] xx $normalizedMethod ${_hostLabel(url)} '
      'error=$error$suffix',
    );
  }

  String describeError(Object error, {required String fallbackMessage}) {
    if (error is DioException) {
      final responseData = error.response?.data;
      if (responseData is Map<String, dynamic>) {
        final apiError = responseData['error'];
        if (apiError is String && apiError.trim().isNotEmpty) {
          return apiError.trim();
        }

        final apiMessage = responseData['message'];
        if (apiMessage is String && apiMessage.trim().isNotEmpty) {
          return apiMessage.trim();
        }
      }

      final rawMessage = error.message;
      if (rawMessage != null && rawMessage.trim().isNotEmpty) {
        return rawMessage.trim();
      }
    }

    return fallbackMessage;
  }

  Future<Response<T>> request<T>({
    required String method,
    required String path,
    Object? data,
    Options? options,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (_baseUrls.isEmpty) {
      throw StateError('No backend base URLs configured');
    }

    final normalizedPath = path.startsWith('/') ? path : '/$path';
    Object? lastError;

    for (var i = 0; i < _baseUrls.length; i++) {
      final url = '${_baseUrls[i]}$normalizedPath';
      final canTryNext = i < _baseUrls.length - 1;
      _logRequestAttempt(
        method: method,
        url: url,
        attempt: i + 1,
        totalAttempts: _baseUrls.length,
      );
      try {
        final response = await _dio.request<T>(
          url,
          data: data,
          queryParameters: queryParameters,
          options: (options ?? Options()).copyWith(method: method),
        );
        _logResponse(method: method, url: url, response: response);
        return response;
      } catch (error) {
        lastError = error;
        final retryForNetworkError = canTryNext && _isNetworkDioError(error);
        _logFailure(
          method: method,
          url: url,
          error: error,
          willRetry: retryForNetworkError,
        );
        if (!canTryNext || !_isNetworkDioError(error)) {
          rethrow;
        }
      }
    }

    throw lastError ?? StateError('Request failed');
  }
}
