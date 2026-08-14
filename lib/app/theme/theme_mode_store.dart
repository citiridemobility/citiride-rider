import 'package:flutter/material.dart';

class CitirideThemeModeStore {
  CitirideThemeModeStore._();

  static final CitirideThemeModeStore instance = CitirideThemeModeStore._();

  final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(
    ThemeMode.dark,
  );

  void update(ThemeMode nextMode) {
    mode.value = nextMode;
  }
}
