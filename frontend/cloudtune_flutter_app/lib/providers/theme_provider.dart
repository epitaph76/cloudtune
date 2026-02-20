import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

class ThemeProvider with ChangeNotifier {
  static const _modeKey = 'cloudtune_theme_mode';
  static const _schemeKey = 'cloudtune_theme_scheme';

  AppVisualMode _mode = AppVisualMode.light;
  AppAccentScheme _scheme = AppAccentScheme.green;
  bool _isReady = false;

  ThemeProvider() {
    _load();
  }

  bool get isReady => _isReady;
  AppVisualMode get mode => _mode;
  AppAccentScheme get scheme => _scheme;

  ThemeMode get themeMode {
    return _mode == AppVisualMode.dark ? ThemeMode.dark : ThemeMode.light;
  }

  ThemeData get lightTheme {
    final palette = AppTheme.palette(AppVisualMode.light, _scheme);
    return AppTheme.buildTheme(palette: palette, brightness: Brightness.light);
  }

  ThemeData get darkTheme {
    final palette = AppTheme.palette(AppVisualMode.dark, _scheme);
    return AppTheme.buildTheme(palette: palette, brightness: Brightness.dark);
  }

  AppPalette get activePalette => AppTheme.palette(_mode, _scheme);

  Future<void> setMode(AppVisualMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _save();
  }

  Future<void> setScheme(AppAccentScheme scheme) async {
    if (_scheme == scheme) return;
    _scheme = scheme;
    notifyListeners();
    await _save();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = _modeFromString(prefs.getString(_modeKey));
    _scheme = _schemeFromString(prefs.getString(_schemeKey));
    _isReady = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, _mode.name);
    await prefs.setString(_schemeKey, _scheme.name);
  }

  AppVisualMode _modeFromString(String? value) {
    return AppVisualMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AppVisualMode.light,
    );
  }

  AppAccentScheme _schemeFromString(String? value) {
    return AppAccentScheme.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AppAccentScheme.green,
    );
  }
}
