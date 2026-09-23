import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/poll_model.dart';
import '../services/api_service.dart';

class VoteScreen extends StatefulWidget {
  const VoteScreen({required this.roomCode, super.key});

  final String roomCode;

  @override
  State<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends State<VoteScreen> {
  late final PollSocket _socket;
  StreamSubscription<PollState>? _subscription;
  Timer? _timer;
  PollState? _poll;
  int? _selectedOption;
  String? _error;

  @override
  void initState() {
    super.initState();
    _socket = PollSocket(
      roomCode: widget.roomCode,
      clientId: const Uuid().v4(),
    );
    _subscription = _socket.states.listen(
      (poll) {
        if (!mounted) return;
        setState(() {
          _poll = poll;
          _error = null;
        });
        _startCountdown();
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = '$error');
      },
    );
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _poll == null || _poll!.timeLeft <= 0) return;
      final remaining = _poll!.timeLeft - 1;
      setState(
        () => _poll = _poll!.copyWith(
          timeLeft: remaining,
          status: remaining == 0 ? 'closed' : null,
        ),
      );
    });
  }

  void _vote(int optionId) {
    if (_selectedOption != null || _poll?.status != 'open') return;
    setState(() => _selectedOption = optionId);
    _socket.castVote(optionId);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    _socket.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final poll = _poll;
    return Scaffold(
      appBar: AppBar(title: Text('Room ${widget.roomCode}')),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!),
              ),
            )
          : poll == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  poll.topic,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  poll.status == 'open'
                      ? '${poll.timeLeft}s remaining'
                      : 'Poll closed',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                ...poll.options.map(
                  (option) => _OptionResult(
                    option: option,
                    totalVotes: poll.options.fold(
                      0,
                      (total, item) => total + item.votes,
                    ),
                    selected: _selectedOption == option.id,
                    enabled: _selectedOption == null && poll.status == 'open',
                    onTap: () => _vote(option.id),
                  ),
                ),
              ],
            ),
    );
  }
}

class _OptionResult extends StatelessWidget {
  const _OptionResult({
    required this.option,
    required this.totalVotes,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final PollOption option;
  final int totalVotes;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final percentage = totalVotes == 0 ? 0.0 : option.votes / totalVotes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: enabled ? onTap : null,
            style: OutlinedButton.styleFrom(
              backgroundColor: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              padding: const EdgeInsets.all(16),
            ),
            child: Row(
              children: [
                Expanded(child: Text(option.text)),
                Text('${(percentage * 100).round()}% (${option.votes})'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: percentage),
        ],
      ),
    );
  }
}
