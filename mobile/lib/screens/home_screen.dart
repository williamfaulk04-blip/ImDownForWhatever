import '../theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/poll_model.dart';
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
  List<RoomSession> _recentRooms = const [];
  bool _busy = false;
  String _loadingStatus = 'Preparing your room…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecentRooms();
  }

  Future<void> _loadRecentRooms() async {
    final rooms = await SessionStore.readRecent();
    if (mounted) setState(() => _recentRooms = rooms);
  }

  Future<void> _forgetRoom(RoomSession room) async {
    await SessionStore.remove(room.roomCode);
    await _loadRecentRooms();
  }

  void _rejoinRoom(RoomSession room) {
    _name.text = room.name;
    _code.text = room.roomCode;
    _enter(true);
  }

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
      if (mounted) {
        setState(() => _busy = false);
        await _loadRecentRooms();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ImDownForWhatever'),
      actions: const [AppearanceButton()],
    ),
    body: _busy
        ? RoomLoadingView(status: _loadingStatus)
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.explore_rounded,
                        size: 36,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
                    decoration: const InputDecoration(labelText: 'Your name'),
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
                    ),
                    onSubmitted: (_) => _enter(true),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => _enter(true),
                    child: const Text('Join Room'),
                  ),
                  if (_recentRooms.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 28, bottom: 8),
                      child: Text('Recent rooms'),
                    ),
                    for (final room in _recentRooms)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.meeting_room_outlined),
                          title: Text('Room ${room.roomCode}'),
                          subtitle: Text('Rejoin as ${room.name}'),
                          onTap: _busy ? null : () => _rejoinRoom(room),
                          trailing: IconButton(
                            tooltip: 'Forget room ${room.roomCode}',
                            onPressed: _busy ? null : () => _forgetRoom(room),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                  ],
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
