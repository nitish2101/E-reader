import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/repositories/settings_repository.dart';

part 'theme_state.dart';

class ThemeCubit extends Cubit<ThemeState> {
  final SettingsRepository settingsRepository;

  ThemeCubit({required this.settingsRepository})
      : super(ThemeState(themeMode: settingsRepository.getThemeMode())) {
    // Listen to theme changes from other sources
    settingsRepository.watchThemeMode().listen((themeMode) {
      emit(ThemeState(themeMode: themeMode));
    });
  }

  void setThemeMode(ThemeMode mode) {
    settingsRepository.setThemeMode(mode);
    emit(ThemeState(themeMode: mode));
  }

  void toggleTheme() {
    final newMode = state.themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
    setThemeMode(newMode);
  }

  void setSystemTheme() {
    setThemeMode(ThemeMode.system);
  }

  bool get isDarkMode => state.themeMode == ThemeMode.dark;
  bool get isLightMode => state.themeMode == ThemeMode.light;
  bool get isSystemMode => state.themeMode == ThemeMode.system;
}
