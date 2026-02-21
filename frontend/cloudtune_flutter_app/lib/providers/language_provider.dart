import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider with ChangeNotifier {
  static const _languageCodeKey = 'cloudtune_language_code';

  Locale _locale = const Locale('ru');
  bool _isReady = false;

  LanguageProvider() {
    _load();
  }

  Locale get locale => _locale;
  bool get isReady => _isReady;

  Future<void> setLocale(Locale locale) async {
    if (_locale.languageCode == locale.languageCode) return;
    _locale = locale;
    notifyListeners();
    await _save();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_languageCodeKey);
    if (code != null && code.isNotEmpty) {
      _locale = Locale(code);
    }
    _isReady = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageCodeKey, _locale.languageCode);
  }
}
