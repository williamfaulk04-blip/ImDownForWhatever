import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import 'vote_screen.dart';
import '../widgets/room_loading_view.dart';

class RoomCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.toUpperCase().replaceAll(
      RegExp('[^A-Z0-9]'),
      '',
    );
    final limited = text.length > 4 ? text.substring(0, 4) : text;
    return TextEditingValue(
      text: limited,
      selection: TextSelection.collapsed(offset: limited.length),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String _loadingStatus = 'Preparing your room…';
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _enter(bool joining) async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.isEmpty || (joining && _code.text.length != 4)) {
      setState(
        () => _error = name.isEmpty
            ? 'Enter your name first.'
            : 'Enter a 4-character room code.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ApiService();
    try {
      final session = await api.enter(
        name: name,
        code: joining ? _code.text : null,
        onProgress: (status) {
          if (mounted) setState(() => _loadingStatus = status);
        },
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => VoteScreen(session: session)),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiFailure ? error.message : 'Could not reach the server. Check your connection and try again.',
        );
      }
    } finally {
      api.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ImDownForWhatever')),
    body: _busy
        ? RoomLoadingView(status: _loadingStatus)
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Good friends.\nOne plan.',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Make a room, invite your friends, and decide together.',
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _name,
                    maxLength: 40,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _enter(false),
                    icon: const Icon(Icons.add),
                    label: const Text('Create Room'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Divider(),
                  ),
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    inputFormatters: [RoomCodeFormatter()],
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Room code',
                      hintText: 'AB12',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _enter(true),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => _enter(true),
                    child: const Text('Join Room'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
  );
}
