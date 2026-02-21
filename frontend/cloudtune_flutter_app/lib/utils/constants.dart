class Constants {
  // API Constants
  // Override in run/build with:
  // --dart-define=API_BASE_URL=https://api.your-domain.com
  static const String primaryBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api-mp3-player.ru',
  );
  static const List<String> fallbackBaseUrls = [
    'https://api.api-mp3-player.ru',
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
