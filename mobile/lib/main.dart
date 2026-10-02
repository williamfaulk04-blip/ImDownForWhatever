import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'services/api_service.dart';
import 'settings/app_settings.dart';
import 'theme/app_theme.dart';

void main() => runApp(const FastPollApp());

class FastPollApp extends StatefulWidget {
  const FastPollApp({super.key});
  @override
  State<FastPollApp> createState() => _FastPollAppState();
}

class _FastPollAppState extends State<FastPollApp> {
  ThemeMode _mode = ThemeMode.system;
  String? _serverUrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final savedAppearance = preferences.getString('appearance');
    final savedServer = preferences.getString('server_base_url');
    try {
      ApiConfig.setRuntimeBaseUrl(savedServer);
    } on FormatException {
      ApiConfig.setRuntimeBaseUrl(null);
      await preferences.remove('server_base_url');
    }
    if (!mounted) return;
    setState(() {
      _mode = ThemeMode.values.firstWhere(
        (mode) => mode.name == savedAppearance,
        orElse: () => ThemeMode.system,
      );
      _serverUrl = ApiConfig.usesRuntimeBaseUrl ? ApiConfig.baseUrl : null;
      _ready = true;
    });
  }

  Future<void> _change(ThemeMode mode) async {
    setState(() => _mode = mode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('appearance', mode.name);
  }

  Future<void> _changeServer(String? serverUrl) async {
    ApiConfig.setRuntimeBaseUrl(serverUrl);
    setState(
      () =>
          _serverUrl = ApiConfig.usesRuntimeBaseUrl ? ApiConfig.baseUrl : null,
    );
    final preferences = await SharedPreferences.getInstance();
    if (_serverUrl == null) {
      await preferences.remove('server_base_url');
    } else {
      await preferences.setString('server_base_url', _serverUrl!);
    }
  }

  @override
  Widget build(BuildContext context) => AppSettingsScope(
    themeMode: _mode,
    serverUrl: _serverUrl ?? ApiConfig.defaultBaseUrl,
    usesCustomServer: _serverUrl != null,
    onThemeChanged: _change,
    onServerChanged: _changeServer,
    child: MaterialApp(
      title: 'ImDownForWhatever',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: _mode,
      home: _ready
          ? const HomeScreen()
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
  );
}
