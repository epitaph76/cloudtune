import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  User? _currentUser;
  User? get currentUser => _currentUser;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isCheckingAuth = true;
  bool get isCheckingAuth => _isCheckingAuth;

  AuthProvider() {
    _checkInitialAuthStatus();
  }

  Future<void> _checkInitialAuthStatus() async {
    _isCheckingAuth = true;
    notifyListeners();

    try {
      final isLoggedIn = await _authService.isLoggedIn();
      _currentUser = isLoggedIn ? await _authService.getCachedUser() : null;
    } catch (e) {
      // Log error in production
    } finally {
      _isCheckingAuth = false;
      notifyListeners();
    }
  }

  Future<bool> register(String email, String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.register(email, username, password);

    _isLoading = false;

    if (result['success']) {
      _currentUser = result['user'];
      // Cache user details
      if (_currentUser != null) {
        await _authService.cacheUser(_currentUser!);
      }
      notifyListeners();
      return true;
    } else {
      _errorMessage = result['message']?.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.login(email, password);

    _isLoading = false;

    if (result['success']) {
      _currentUser = result['user'];
      // Cache user details
      if (_currentUser != null) {
        await _authService.cacheUser(_currentUser!);
      }
      notifyListeners();
      return true;
    } else {
      _errorMessage = result['message']?.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _currentUser = null;
    notifyListeners();
  }

  Future<bool> checkAuthStatus() async {
    final isLoggedIn = await _authService.isLoggedIn();
    final nextUser = isLoggedIn ? await _authService.getCachedUser() : null;
    final userChanged =
        _currentUser?.id != nextUser?.id ||
        _currentUser?.email != nextUser?.email ||
        _currentUser?.username != nextUser?.username;
    if (userChanged) {
      _currentUser = nextUser;
      notifyListeners();
    }
    return isLoggedIn;
  }
}
