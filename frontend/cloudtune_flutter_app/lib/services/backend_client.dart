import 'dart:io';

import 'package:dio/dio.dart';

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
      try {
        return await _dio.request<T>(
          url,
          data: data,
          queryParameters: queryParameters,
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

    throw lastError ?? StateError('Request failed');
  }
}
