import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

typedef YandexDiskScanProgressCallback =
    void Function(YandexDiskScanProgress progress);

class YandexDiskScanProgress {
  const YandexDiskScanProgress({
    required this.processedDirectories,
    required this.pendingDirectories,
    required this.foundAudioFiles,
  });

  final int processedDirectories;
  final int pendingDirectories;
  final int foundAudioFiles;
}

class YandexDiskAudioEntry {
  const YandexDiskAudioEntry({
    required this.path,
    required this.name,
    required this.size,
    required this.mimeType,
    required this.mediaType,
    required this.modified,
  });

  final String path;
  final String name;
  final int? size;
  final String? mimeType;
  final String? mediaType;
  final DateTime? modified;
}

class YandexDiskService {
  YandexDiskService({Dio? dio, FlutterSecureStorage? secureStorage})
    : _dio = dio ?? Dio(_dioOptions),
      _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static final BaseOptions _dioOptions = BaseOptions(
    baseUrl: 'https://cloud-api.yandex.net',
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
  );
  static const Set<String> _supportedAudioExtensions = <String>{
    '.mp3',
    '.wav',
    '.flac',
    '.m4a',
    '.mp4',
    '.aac',
    '.ogg',
    '.opus',
  };
  static const int _defaultPageSize = 200;
  static const int _maxAttempts = 3;
  static const String _legacyTokenStorageKey =
      'cloudtune_yandex_disk_oauth_token_legacy';
  static const List<Duration> _retryDelays = <Duration>[
    Duration(milliseconds: 650),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  final Dio _dio;
  final FlutterSecureStorage _secureStorage;

  String buildOAuthAuthorizeUrl({required String clientId}) {
    final trimmedClientId = clientId.trim();
    if (trimmedClientId.isEmpty) {
      throw StateError('YANDEX_OAUTH_CLIENT_ID is empty');
    }

    return Uri.https('oauth.yandex.ru', '/authorize', {
      'response_type': 'token',
      'client_id': trimmedClientId,
      'force_confirm': 'yes',
    }).toString();
  }

  String? extractAccessToken(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final directToken = uri.queryParameters['access_token'];
      if (directToken != null && directToken.trim().isNotEmpty) {
        return directToken.trim();
      }

      final fragment = uri.fragment.trim();
      if (fragment.isNotEmpty) {
        try {
          final fragmentParams = Uri.splitQueryString(fragment);
          final token = fragmentParams['access_token'];
          if (token != null && token.trim().isNotEmpty) {
            return token.trim();
          }
        } catch (_) {
          // Ignore malformed URL fragment and keep fallback parsing below.
        }
      }
    }

    final match = RegExp(r'access_token=([^&#\s]+)').firstMatch(trimmed);
    if (match != null) {
      final value = match.group(1);
      if (value != null && value.trim().isNotEmpty) {
        return Uri.decodeQueryComponent(value).trim();
      }
    }

    if (trimmed.contains(' ') || trimmed.contains('&')) return null;
    return trimmed;
  }

  Future<void> saveAccessToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) return;

    try {
      await _secureStorage.write(
        key: Constants.yandexDiskOAuthTokenKey,
        value: normalized,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyTokenStorageKey);
      return;
    } catch (_) {
      // Fall back to shared preferences if secure storage is unavailable.
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_legacyTokenStorageKey, normalized);
  }

  Future<String?> readAccessToken() async {
    try {
      final secureToken = await _secureStorage.read(
        key: Constants.yandexDiskOAuthTokenKey,
      );
      if (secureToken != null && secureToken.trim().isNotEmpty) {
        return secureToken.trim();
      }
    } catch (_) {
      // Ignore and fallback to legacy storage.
    }

    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_legacyTokenStorageKey);
    if (legacyToken == null || legacyToken.trim().isEmpty) {
      return null;
    }

    try {
      await _secureStorage.write(
        key: Constants.yandexDiskOAuthTokenKey,
        value: legacyToken.trim(),
      );
      await prefs.remove(_legacyTokenStorageKey);
    } catch (_) {
      // Keep legacy token if secure storage remains unavailable.
    }

    return legacyToken.trim();
  }

  Future<void> clearAccessToken() async {
    try {
      await _secureStorage.delete(key: Constants.yandexDiskOAuthTokenKey);
    } catch (_) {
      // Ignore.
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyTokenStorageKey);
  }

  Future<List<YandexDiskAudioEntry>> scanAudioFiles({
    required String accessToken,
    String rootPath = 'disk:/',
    int pageSize = _defaultPageSize,
    CancelToken? cancelToken,
    YandexDiskScanProgressCallback? onProgress,
  }) async {
    final token = accessToken.trim();
    if (token.isEmpty) {
      throw StateError('Yandex OAuth token is empty');
    }

    final pendingDirectories = Queue<String>()..add(rootPath);
    final processedDirectories = <String>{};
    final seenAudioPaths = <String>{};
    final collected = <YandexDiskAudioEntry>[];
    var handledDirectories = 0;

    while (pendingDirectories.isNotEmpty) {
      _throwIfCanceled(cancelToken);
      final directoryPath = pendingDirectories.removeFirst();
      if (!processedDirectories.add(directoryPath)) continue;

      var offset = 0;
      while (true) {
        _throwIfCanceled(cancelToken);
        final page = await _listDirectoryPage(
          accessToken: token,
          directoryPath: directoryPath,
          offset: offset,
          limit: pageSize,
          cancelToken: cancelToken,
        );

        for (final item in page.items) {
          final itemType = (item['type'] as String?)?.trim().toLowerCase();
          if (itemType == 'dir') {
            final nestedPath = (item['path'] as String?)?.trim();
            if (nestedPath != null &&
                nestedPath.isNotEmpty &&
                !processedDirectories.contains(nestedPath)) {
              pendingDirectories.add(nestedPath);
            }
            continue;
          }
          if (itemType != 'file') continue;

          final itemPath = (item['path'] as String?)?.trim();
          final itemName = (item['name'] as String?)?.trim();
          if (itemPath == null ||
              itemPath.isEmpty ||
              itemName == null ||
              itemName.isEmpty ||
              !seenAudioPaths.add(itemPath)) {
            continue;
          }

          final mimeType = (item['mime_type'] as String?)?.trim().toLowerCase();
          final mediaType = (item['media_type'] as String?)
              ?.trim()
              .toLowerCase();
          if (!_isAudioResource(
            path: itemPath,
            name: itemName,
            mimeType: mimeType,
            mediaType: mediaType,
          )) {
            continue;
          }

          DateTime? modifiedAt;
          final rawModified = item['modified'];
          if (rawModified is String && rawModified.trim().isNotEmpty) {
            modifiedAt = DateTime.tryParse(rawModified.trim());
          }

          collected.add(
            YandexDiskAudioEntry(
              path: itemPath,
              name: itemName,
              size: _asInt(item['size']),
              mimeType: mimeType,
              mediaType: mediaType,
              modified: modifiedAt,
            ),
          );
        }

        offset += page.items.length;
        final exhausted =
            page.items.isEmpty ||
            (page.total != null
                ? offset >= page.total!
                : page.items.length < pageSize);
        if (exhausted) break;
      }

      handledDirectories++;
      onProgress?.call(
        YandexDiskScanProgress(
          processedDirectories: handledDirectories,
          pendingDirectories: pendingDirectories.length,
          foundAudioFiles: collected.length,
        ),
      );
    }

    collected.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return collected;
  }

  Future<File> downloadAudioFile({
    required String accessToken,
    required YandexDiskAudioEntry entry,
    required Directory targetRootDirectory,
    CancelToken? cancelToken,
  }) async {
    final token = accessToken.trim();
    if (token.isEmpty) {
      throw StateError('Yandex OAuth token is empty');
    }

    final segments = _sanitizeRemoteSegments(
      entry.path,
      fallbackName: entry.name,
    );
    final outputPath = p.joinAll(<String>[
      targetRootDirectory.path,
      ...segments,
    ]);
    final outputFile = File(outputPath);
    final tempFile = File('$outputPath.part');

    if (!await outputFile.parent.exists()) {
      await outputFile.parent.create(recursive: true);
    }
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    await _runWithRetry<void>(() async {
      _throwIfCanceled(cancelToken);
      final downloadUrl = await _resolveDownloadUrl(
        accessToken: token,
        resourcePath: entry.path,
        cancelToken: cancelToken,
      );
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      await _dio.download(
        downloadUrl,
        tempFile.path,
        cancelToken: cancelToken,
        options: Options(
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
    }, cancelToken: cancelToken);

    if (await outputFile.exists()) {
      await outputFile.delete();
    }
    return tempFile.rename(outputFile.path);
  }

  Future<String> _resolveDownloadUrl({
    required String accessToken,
    required String resourcePath,
    CancelToken? cancelToken,
  }) async {
    final response = await _requestWithRetry(
      () => _dio.get<Object?>(
        '/v1/disk/resources/download',
        queryParameters: {'path': resourcePath},
        options: Options(
          headers: <String, String>{'Authorization': 'OAuth $accessToken'},
        ),
        cancelToken: cancelToken,
      ),
      cancelToken: cancelToken,
    );

    final payload = _asMap(response.data);
    final href = (payload['href'] as String?)?.trim();
    if (href == null || href.isEmpty) {
      throw StateError('Unable to resolve Yandex.Disk download URL');
    }
    return href;
  }

  Future<_YandexDirectoryPage> _listDirectoryPage({
    required String accessToken,
    required String directoryPath,
    required int offset,
    required int limit,
    CancelToken? cancelToken,
  }) async {
    final response = await _requestWithRetry(
      () => _dio.get<Object?>(
        '/v1/disk/resources',
        queryParameters: <String, dynamic>{
          'path': directoryPath,
          'offset': offset,
          'limit': limit,
          'fields':
              '_embedded.items.path,_embedded.items.type,_embedded.items.name,_embedded.items.mime_type,_embedded.items.media_type,_embedded.items.size,_embedded.items.modified,_embedded.total',
        },
        options: Options(
          headers: <String, String>{'Authorization': 'OAuth $accessToken'},
        ),
        cancelToken: cancelToken,
      ),
      cancelToken: cancelToken,
    );

    final payload = _asMap(response.data);
    final embedded = _asMap(payload['_embedded']);
    return _YandexDirectoryPage(
      items: _asListOfMaps(embedded['items']),
      total: _asInt(embedded['total']),
    );
  }

  Future<Response<Object?>> _requestWithRetry(
    Future<Response<Object?>> Function() request, {
    CancelToken? cancelToken,
  }) async {
    return _runWithRetry<Response<Object?>>(request, cancelToken: cancelToken);
  }

  Future<T> _runWithRetry<T>(
    Future<T> Function() action, {
    CancelToken? cancelToken,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      _throwIfCanceled(cancelToken);
      try {
        return await action();
      } on DioException catch (error) {
        if (error.type == DioExceptionType.cancel ||
            !_isRetryableDioError(error) ||
            attempt >= _maxAttempts) {
          rethrow;
        }
        lastError = error;
        await Future<void>.delayed(_retryDelayForAttempt(attempt));
      } catch (error) {
        if (attempt >= _maxAttempts) rethrow;
        lastError = error;
        await Future<void>.delayed(_retryDelayForAttempt(attempt));
      }
    }

    throw StateError('Unexpected retry loop exit: $lastError');
  }

  bool _isRetryableDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 429) return true;
    if (statusCode != null && statusCode >= 500 && statusCode <= 599) {
      return true;
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
        return false;
    }
  }

  Duration _retryDelayForAttempt(int attempt) {
    final index = attempt - 1;
    if (index < 0) return _retryDelays.first;
    if (index >= _retryDelays.length) return _retryDelays.last;
    return _retryDelays[index];
  }

  bool _isAudioResource({
    required String path,
    required String name,
    String? mimeType,
    String? mediaType,
  }) {
    if (mimeType != null && mimeType.startsWith('audio/')) return true;
    if (mediaType == 'audio') return true;

    final nameExtension = p.extension(name).toLowerCase();
    if (_supportedAudioExtensions.contains(nameExtension)) return true;

    final pathExtension = p.extension(path).toLowerCase();
    return _supportedAudioExtensions.contains(pathExtension);
  }

  List<String> _sanitizeRemoteSegments(
    String rawPath, {
    required String fallbackName,
  }) {
    var normalized = rawPath.trim().replaceAll('\\', '/');
    final colonIndex = normalized.indexOf(':');
    if (colonIndex != -1) {
      normalized = normalized.substring(colonIndex + 1);
    }
    normalized = normalized.replaceFirst(RegExp(r'^/+'), '');

    final segments = normalized
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .map(_sanitizePathSegment)
        .toList();

    if (segments.isEmpty) {
      segments.add(_sanitizePathSegment(fallbackName));
    }

    final fileSegment = segments.last;
    final extension = p.extension(fileSegment).toLowerCase();
    if (extension.isEmpty) {
      final fallbackExtension = p.extension(fallbackName).toLowerCase();
      if (fallbackExtension.isNotEmpty) {
        segments[segments.length - 1] = '$fileSegment$fallbackExtension';
      }
    }
    return segments;
  }

  String _sanitizePathSegment(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    if (sanitized.isEmpty) return '_';
    return sanitized;
  }

  void _throwIfCanceled(CancelToken? cancelToken) {
    if (cancelToken?.isCancelled != true) return;
    throw DioException(
      requestOptions: RequestOptions(path: 'yandex-disk'),
      type: DioExceptionType.cancel,
      error: cancelToken?.cancelError,
    );
  }

  int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  Map<String, dynamic> _asMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asListOfMaps(Object? raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}

class _YandexDirectoryPage {
  const _YandexDirectoryPage({required this.items, required this.total});

  final List<Map<String, dynamic>> items;
  final int? total;
}
