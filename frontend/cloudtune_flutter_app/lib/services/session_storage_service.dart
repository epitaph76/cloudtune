import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../utils/constants.dart';

class SessionStorageService {
  SessionStorageService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  Future<void> saveToken(String token) async {
    if (token.isEmpty) return;
    try {
      await _secureStorage.write(key: Constants.tokenKey, value: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(Constants.tokenKey);
      return;
    } catch (_) {
      // Fall back to shared preferences to keep app usable on unsupported hosts.
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(Constants.tokenKey, token);
  }

  Future<String?> readToken() async {
    try {
      final secureToken = await _secureStorage.read(key: Constants.tokenKey);
      if (secureToken != null && secureToken.isNotEmpty) {
        return secureToken;
      }
    } catch (_) {
      // Ignore and use migration fallback below.
    }

    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(Constants.tokenKey);
    if (legacyToken == null || legacyToken.isEmpty) {
      return null;
    }

    try {
      await _secureStorage.write(key: Constants.tokenKey, value: legacyToken);
      await prefs.remove(Constants.tokenKey);
    } catch (_) {
      // Keep legacy token if secure storage is unavailable.
    }

    return legacyToken;
  }

  Future<void> clearToken() async {
    try {
      await _secureStorage.delete(key: Constants.tokenKey);
    } catch (_) {
      // Ignore.
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Constants.tokenKey);
  }

  Future<User?> getCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString(Constants.userCacheKey);
    if (userData == null || userData.isEmpty) {
      return null;
    }

    try {
      final decoded = json.decode(userData);
      if (decoded is Map<String, dynamic>) {
        return User.fromJson(decoded);
      }
      if (decoded is Map) {
        return User.fromJson(Map<String, dynamic>.from(decoded));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(Constants.userCacheKey, json.encode(user.toJson()));
  }

  Future<void> clearCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Constants.userCacheKey);
  }
}
