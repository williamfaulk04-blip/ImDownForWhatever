import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../settings/app_settings.dart';

class SettingsButton extends StatelessWidget {
  const SettingsButton({this.canEditServer = true, this.onClosed, super.key});

  final bool canEditServer;
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    if (AppSettingsScope.maybeOf(context) == null) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'Settings',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(canEditServer: canEditServer),
          ),
        );
        onClosed?.call();
      },
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.canEditServer, super.key});

  final bool canEditServer;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _server = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _server.text = AppSettingsScope.of(context).serverUrl;
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  Future<void> _saveServer() async {
    if (_saving || !widget.canEditServer) return;
    String normalized;
    try {
      normalized = ApiConfig.normalizeBaseUrl(_server.text);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    await AppSettingsScope.of(context).onServerChanged(normalized);
    if (!mounted) return;
    _server.text = ApiConfig.baseUrl;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server saved. New rooms will use it.')),
    );
  }

  Future<void> _useDefaultServer() async {
    if (_saving || !widget.canEditServer) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    await AppSettingsScope.of(context).onServerChanged(null);
    if (!mounted) return;
    _server.text = ApiConfig.baseUrl;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Using the default development server.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Connection', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                widget.canEditServer
                    ? 'Everyone joining the same rooms must use this server address.'
                    : 'Return home before changing servers. This keeps the active room connected to one backend.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _server,
                enabled: widget.canEditServer && !_saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Server address',
                  hintText: 'https://example.trycloudflare.com',
                  errorText: _error,
                ),
                onSubmitted: (_) => _saveServer(),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.canEditServer && !_saving
                    ? _saveServer
                    : null,
                icon: const Icon(Icons.cloud_done_outlined),
                label: const Text('Save server'),
              ),
              if (settings.usesCustomServer)
                TextButton(
                  onPressed: widget.canEditServer && !_saving
                      ? _useDefaultServer
                      : null,
                  child: const Text('Use default development server'),
                ),
              const SizedBox(height: 32),
              Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final entry in const {
                ThemeMode.system: ('Use device theme', Icons.brightness_auto),
                ThemeMode.light: ('Light mode', Icons.light_mode_outlined),
                ThemeMode.dark: ('Dark mode', Icons.dark_mode_outlined),
              }.entries)
                Card(
                  child: ListTile(
                    leading: Icon(entry.value.$2),
                    title: Text(entry.value.$1),
                    trailing: settings.themeMode == entry.key
                        ? const Icon(Icons.check_circle)
                        : null,
                    onTap: () => settings.onThemeChanged(entry.key),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
