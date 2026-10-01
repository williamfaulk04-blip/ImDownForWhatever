import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() => runApp(const FastPollApp());

class FastPollApp extends StatefulWidget {
  const FastPollApp({super.key});
  @override
  State<FastPollApp> createState() => _FastPollAppState();
}

class _FastPollAppState extends State<FastPollApp> {
  ThemeMode _mode = ThemeMode.system;
  bool _chosen = false;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('appearance');
    if (mounted && !_chosen) {
      setState(
        () => _mode = ThemeMode.values.firstWhere(
          (mode) => mode.name == saved,
          orElse: () => ThemeMode.system,
        ),
      );
    }
  }

  Future<void> _change(ThemeMode mode) async {
    _chosen = true;
    setState(() => _mode = mode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('appearance', mode.name);
  }

  @override
  Widget build(BuildContext context) => AppearanceScope(
    mode: _mode,
    onChanged: _change,
    child: MaterialApp(
      title: 'ImDownForWhatever',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: _mode,
      home: const HomeScreen(),
    ),
  );
}
