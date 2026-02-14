class Constants {
  // API Constants
  static const String baseUrl = 'http://192.168.31.128:8080';
  
  // Storage Keys
  static const String tokenKey = 'cloudtune_token';
  
  // Validation Messages
  static const String emailRequired = 'Пожалуйста, введите email';
  static const String validEmail = 'Введите действительный email';
  static const String usernameRequired = 'Пожалуйста, введите имя пользователя';
  static const String usernameLength = 'Имя пользователя должно быть не менее 3 символов';
  static const String passwordRequired = 'Пожалуйста, введите пароль';
  static const String passwordLength = 'Пароль должен быть не менее 6 символов';
  static const String confirmPasswordRequired = 'Пожалуйста, подтвердите пароль';
  static const String passwordsNotMatch = 'Пароли не совпадают';
  
  // Success Messages
  static const String registrationSuccess = 'Регистрация успешна!';
  
  // Error Messages
  static const String registrationFailed = 'Регистрация не удалась';
}