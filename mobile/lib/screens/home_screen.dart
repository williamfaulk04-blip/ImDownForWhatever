import 'package:flutter/material.dart';

import 'host_screen.dart';
import 'vote_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _roomController = TextEditingController();

  @override
  void dispose() {
    _roomController.dispose();
    super.dispose();
  }

  void _join() {
    final code = _roomController.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 4-character room code.')),
      );
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => VoteScreen(roomCode: code)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FastPoll')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Decide together, fast.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const HostScreen()),
                  ),
                  icon: const Icon(Icons.add_chart),
                  label: const Text('Create Poll'),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _roomController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Room code',
                    prefixIcon: Icon(Icons.meeting_room),
                  ),
                  onSubmitted: (_) => _join(),
                ),
                FilledButton.tonal(
                  onPressed: _join,
                  child: const Text('Join Room'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
