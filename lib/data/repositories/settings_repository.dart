import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SettingsRepository {
  static const String _boxName = 'settings';
  static const String _themeModeKey = 'theme_mode';
  static const String _searchAnnasArchiveKey = 'search_annas_archive';
  static const String _searchLibgenKey = 'search_libgen';
  static const String _autoSaveProgressKey = 'auto_save_progress';
  static const String _downloadFormatKey = 'download_format';
  static const String _appLanguageKey = 'app_language';

  Box get _box => Hive.box(_boxName);

  // Theme Mode
  ThemeMode getThemeMode() {
    final themeIndex = _box.get(_themeModeKey, defaultValue: 0);
    return ThemeMode.values[themeIndex];
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _box.put(_themeModeKey, mode.index);
  }

  // Search Sources
  bool getSearchAnnasArchive() {
    return _box.get(_searchAnnasArchiveKey, defaultValue: true);
  }

  Future<void> setSearchAnnasArchive(bool value) async {
    await _box.put(_searchAnnasArchiveKey, value);
  }

  bool getSearchLibgen() {
    return _box.get(_searchLibgenKey, defaultValue: true);
  }

  Future<void> setSearchLibgen(bool value) async {
    await _box.put(_searchLibgenKey, value);
  }

  // Auto-save Reading Progress
  bool getAutoSaveProgress() {
    return _box.get(_autoSaveProgressKey, defaultValue: true);
  }

  Future<void> setAutoSaveProgress(bool value) async {
    await _box.put(_autoSaveProgressKey, value);
  }

  // Preferred Download Format
  String getDownloadFormat() {
    return _box.get(_downloadFormatKey, defaultValue: 'epub');
  }

  Future<void> setDownloadFormat(String format) async {
    await _box.put(_downloadFormatKey, format);
  }

  // App Language
  String getAppLanguage() {
    return _box.get(_appLanguageKey, defaultValue: 'en');
  }

  Future<void> setAppLanguage(String language) async {
    await _box.put(_appLanguageKey, language);
  }

  // Clear all settings
  Future<void> clearAllSettings() async {
    await _box.clear();
  }

  // Watch for theme changes
  Stream<ThemeMode> watchThemeMode() {
    return _box.watch(key: _themeModeKey).map((_) => getThemeMode());
  }
}
