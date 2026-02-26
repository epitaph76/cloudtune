import 'package:flutter/foundation.dart';

class Constants {
  // API Constants
  // Override in run/build with:
  // --dart-define=API_BASE_URL=https://api.your-domain.com
  static const String primaryBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api-mp3-player.ru',
  );
  // Keep fallback disabled by default so every client talks to one backend.
  // Enable only for explicit diagnostics:
  // --dart-define=API_ENABLE_FALLBACK_URLS=true
  static const bool _fallbackRequestedByDefine = bool.fromEnvironment(
    'API_ENABLE_FALLBACK_URLS',
    defaultValue: false,
  );

  // Safety: fallback URLs are never enabled in release builds.
  static bool get enableFallbackBaseUrls =>
      !kReleaseMode && _fallbackRequestedByDefine;

  static const List<String> _fallbackBaseUrlsRaw = [
    'http://168.222.252.159',
    'http://168.222.252.159:8080',
  ];
  static List<String> get fallbackBaseUrls =>
      enableFallbackBaseUrls ? _fallbackBaseUrlsRaw : const <String>[];

  static List<String> get activeBaseUrls => <String>[
    primaryBaseUrl,
    ...fallbackBaseUrls,
  ];

  // Storage Keys
  static const String tokenKey = 'cloudtune_token';
  static const String userCacheKey = 'cloudtune_user_cache';

  // Validation Messages
  static const String emailRequired = 'Пожалуйста, введите email';
  static const String validEmail = 'Введите действительный email';
  static const String usernameRequired = 'Пожалуйста, введите имя пользователя';
  static const String usernameLength =
      'Имя пользователя должно быть не менее 3 символов';
  static const String passwordRequired = 'Пожалуйста, введите пароль';
  static const String passwordLength = 'Пароль должен быть не менее 6 символов';
  static const String confirmPasswordRequired =
      'Пожалуйста, подтвердите пароль';
  static const String passwordsNotMatch = 'Пароли не совпадают';

  // Success Messages
  static const String registrationSuccess = 'Регистрация успешна!';

  // Error Messages
  static const String registrationFailed = 'Регистрация не удалась';
}
