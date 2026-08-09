import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/settings_repository.dart';
import '../domain/company_settings.dart';

/// Company settings for the current user's company.
final companySettingsProvider = StreamProvider<CompanySettings>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) {
    return Stream.value(const CompanySettings(companyId: 'default'));
  }
  return ref.watch(settingsRepositoryProvider).watch(user.companyId);
});

/// App theme mode, persisted in SharedPreferences.
final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'themeMode';

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key);
    if (v != null) {
      state = ThemeMode.values.firstWhere(
        (m) => m.name == v,
        orElse: () => ThemeMode.system,
      );
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
