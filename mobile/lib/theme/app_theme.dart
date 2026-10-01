import 'package:flutter/material.dart';

ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF167D8D),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFF75D6CF) : const Color(0xFF126B68),
        onPrimary: dark ? const Color(0xFF003735) : Colors.white,
        secondary: dark ? const Color(0xFFFFC18F) : const Color(0xFF9D4D21),
        surface: dark ? const Color(0xFF142527) : const Color(0xFFFFFCF5),
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
  return base.copyWith(
    scaffoldBackgroundColor: dark
        ? const Color(0xFF0D1B1E)
        : const Color(0xFFF5F2E9),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF0D1B1E) : const Color(0xFFF5F2E9),
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      shape: shape,
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: shape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: shape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.all(18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
  );
}

class AppearanceScope extends InheritedWidget {
  const AppearanceScope({
    required this.mode,
    required this.onChanged,
    required super.child,
    super.key,
  });
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;
  static AppearanceScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>();
  @override
  bool updateShouldNotify(AppearanceScope oldWidget) => mode != oldWidget.mode;
}

class AppearanceButton extends StatelessWidget {
  const AppearanceButton({super.key});
  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.of(context);
    if (appearance == null) return const SizedBox.shrink();
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Appearance',
      icon: const Icon(Icons.contrast_rounded),
      initialValue: appearance.mode,
      onSelected: appearance.onChanged,
      itemBuilder: (_) => [
        for (final entry in const {
          ThemeMode.system: 'Use device theme',
          ThemeMode.light: 'Light mode',
          ThemeMode.dark: 'Dark mode',
        }.entries)
          CheckedPopupMenuItem(
            value: entry.key,
            checked: appearance.mode == entry.key,
            child: Text(entry.value),
          ),
      ],
    );
  }
}
