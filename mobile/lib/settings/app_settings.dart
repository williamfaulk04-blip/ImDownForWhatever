import 'package:flutter/material.dart';

class AppSettingsScope extends InheritedWidget {
  const AppSettingsScope({
    required this.themeMode,
    required this.serverUrl,
    required this.usesCustomServer,
    required this.onThemeChanged,
    required this.onServerChanged,
    required super.child,
    super.key,
  });

  final ThemeMode themeMode;
  final String serverUrl;
  final bool usesCustomServer;
  final Future<void> Function(ThemeMode mode) onThemeChanged;
  final Future<void> Function(String? serverUrl) onServerChanged;

  static AppSettingsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();

  static AppSettingsScope of(BuildContext context) {
    final settings = maybeOf(context);
    assert(
      settings != null,
      'AppSettingsScope was not found in the widget tree.',
    );
    return settings!;
  }

  @override
  bool updateShouldNotify(AppSettingsScope oldWidget) =>
      themeMode != oldWidget.themeMode ||
      serverUrl != oldWidget.serverUrl ||
      usesCustomServer != oldWidget.usesCustomServer;
}
