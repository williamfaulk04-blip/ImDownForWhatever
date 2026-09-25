import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/poll_model.dart';
import '../services/api_service.dart';
import 'host_screen.dart';
import 'poll_results_screen.dart';
import '../widgets/room_loading_view.dart';

class VoteScreen extends StatefulWidget {
  const VoteScreen({required this.session, this.socket, super.key});
  final RoomSession session;
  final RoomSocket? socket;
  @override
  State<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends State<VoteScreen> {
  late final RoomSocket _socket;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  RoomState? _room;
  bool _connected = false;
  bool _busy = false;
  bool _pendingVote = false;
  bool _ended = false;
  String? _dismissedResultsPollId;
  String _connectionMessage = 'Connecting to your room…';
  String? _error;
  Timer? _voteTimeout;

  @override
  void initState() {
    super.initState();
    _socket = widget.socket ?? RoomSocket(widget.session);
    _subscription = _socket.events.listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event['event']) {
          case 'STATE_UPDATE':
            final room = RoomState.fromJson(event);
            if (room.poll?.id != _room?.poll?.id ||
                room.poll?.selectedOption != null ||
                room.poll?.status == 'closed') {
              _pendingVote = false;
              _voteTimeout?.cancel();
            }
            _room = room;
            _connected = true;
          case 'CONNECTING':
            _connectionMessage =
                event['message'] as String? ?? 'Connecting to your room…';
            _connected = false;
            _pendingVote = false;
            _voteTimeout?.cancel();
          case 'ERROR':
            _pendingVote = false;
            _voteTimeout?.cancel();
            _error = event['message'] as String;
          case 'SESSION_ENDED':
            _connected = false;
            _ended = true;
            _error = event['message'] as String;
            unawaited(SessionStore.remove(widget.session.roomCode));
        }
      });
    });
    unawaited(_socket.connect());
  }

  Future<void> _control(Future<void> Function(ApiService) action) async {
    if (_busy || !_connected) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ApiService();
    try {
      await action(api);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiFailure
              ? error.message
              : 'Could not reach the server. Try again.',
        );
      }
    } finally {
      api.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _vote(PollState poll, int option) {
    if (!_connected ||
        _pendingVote ||
        poll.selectedOption != null ||
        poll.status != 'open') {
      return;
    }
    setState(() {
      _pendingVote = true;
      _error = null;
    });
    _socket.vote(poll.id, option);
    _voteTimeout?.cancel();
    _voteTimeout = Timer(const Duration(seconds: 8), () {
      if (mounted && _pendingVote) {
        setState(() {
          _pendingVote = false;
          _error = 'Vote confirmation is delayed. You can retry; only your first vote counts.';
        });
      }
    });
  }

  @override
  void dispose() {
    _voteTimeout?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_socket.close());
    super.dispose();
  }

  void _createNextPoll() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HostScreen(session: widget.session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final poll = room?.poll;
    final showResults =
        !_ended &&
        poll != null &&
        poll.status == 'closed' &&
        _dismissedResultsPollId != poll.id;
    void backToLobby() => setState(() => _dismissedResultsPollId = poll?.id);
    return PopScope(
      canPop: !showResults,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && showResults) backToLobby();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: showResults
            ? PollResultsScreen(
                key: ValueKey('results-${poll.id}'),
                roomCode: widget.session.roomCode,
                poll: poll,
                isHost: room!.isHost,
                connected: _connected,
                error: _error,
                onBack: backToLobby,
                onNextPoll: _connected && !_busy ? _createNextPoll : null,
              )
            : _buildRoom(context),
      ),
    );
  }

  Widget _buildRoom(BuildContext context) {
    final room = _room;
    final poll = room?.poll;
    return Scaffold(
      key: const ValueKey('room'),
      appBar: AppBar(
        title: Text('Room ${widget.session.roomCode}'),
        actions: [
          IconButton(
            tooltip: 'Copy room code',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: widget.session.roomCode),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Room code copied')),
                );
              }
            },
          ),
        ],
      ),
      body: room == null && !_ended
          ? RoomLoadingView(status: _connectionMessage)
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (!_connected && !_ended)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(_connectionMessage),
                              const SizedBox(height: 12),
                              const LinearProgressIndicator(),
                            ],
                          ),
                        ),
                      ),
                    if (_error != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  if (_ended) {
                                    Navigator.of(context).pop();
                                  } else {
                                    setState(() => _error = null);
                                  }
                                },
                                child: Text(
                                  _ended ? 'Back to home' : 'Dismiss',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (room != null) ...[
                      Text(
                        room.isHost ? 'You’re the host' : 'You’re in!',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        room.isOpen ? 'Share the code to invite your friends.' : 'Room locked · Existing friends can still reconnect.',
                      ),
                      if (room.isHost)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Allow new friends to join'),
                          value: room.isOpen,
                          onChanged: !_connected || _busy
                              ? null
                              : (open) => _control(
                                  (api) => api.setOpen(widget.session, open),
                                ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Friends · ${room.participants.where((p) => p.online).length} online',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: room.participants
                            .map(
                              (p) => Chip(
                                avatar: Icon(
                                  p.online
                                      ? Icons.circle
                                      : Icons.circle_outlined,
                                  size: 12,
                                ),
                                label: Text(
                                  '${p.name}${p.isHost ? ' · Host' : ''}${p.online ? '' : ' · Away'}',
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(),
                      ),
                      if (poll == null) ...[
                        const Icon(Icons.people_outline, size: 56),
                        const SizedBox(height: 16),
                        Text(
                          'Everyone’s here. What’s the plan?',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          room.isHost
                              ? 'Start a poll when your friends are ready.'
                              : 'Waiting for the host to start a poll.',
                        ),
                      ] else ...[
                        Text(
                          poll.topic,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          poll.status == 'open'
                              ? '${poll.timeLeft}s remaining · ${poll.totalVotes} ${poll.totalVotes == 1 ? 'vote' : 'votes'}'
                              : 'Poll closed · ${poll.totalVotes} ${poll.totalVotes == 1 ? 'vote' : 'votes'}',
                        ),
                        if (poll.status == 'closed')
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(poll.result),
                          ),
                        if (poll.status == 'closed')
                          TextButton(
                            onPressed: () =>
                                setState(() => _dismissedResultsPollId = null),
                            child: const Text('View results'),
                          ),
                        if (_pendingVote)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('Sending your vote…'),
                          ),
                        const SizedBox(height: 16),
                        if (poll.status == 'open')
                          ...poll.options.map(
                            (option) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Semantics(
                                    selected: poll.selectedOption == option.id,
                                    child: OutlinedButton(
                                      key: ValueKey(
                                        'option-${poll.id}-${option.id}',
                                      ),
                                      onPressed:
                                          _connected &&
                                              !_pendingVote &&
                                              poll.status == 'open' &&
                                              poll.selectedOption == null
                                          ? () => _vote(poll, option.id)
                                          : null,
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.all(16),
                                        backgroundColor:
                                            poll.selectedOption == option.id
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(child: Text(option.text)),
                                          Text(
                                            '${option.votes} ${option.votes == 1 ? 'vote' : 'votes'}',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  LinearProgressIndicator(
                                    value: poll.totalVotes == 0
                                        ? 0
                                        : option.votes / poll.totalVotes,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 24),
                      if (room.isHost && poll?.status == 'open')
                        OutlinedButton(
                          onPressed: !_connected || _busy
                              ? null
                              : () => _control(
                                  (api) =>
                                      api.closePoll(widget.session, poll!.id),
                                ),
                          child: const Text('End poll and show result'),
                        ),
                      if (room.isHost && poll?.status != 'open')
                        FilledButton.icon(
                          onPressed: !_connected || _busy
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        HostScreen(session: widget.session),
                                  ),
                                ),
                          icon: const Icon(Icons.poll_outlined),
                          label: Text(
                            poll == null ? 'Create poll' : 'Start another poll',
                          ),
                        ),
                      if (!room.isHost && poll?.status == 'closed')
                        const Text(
                          'The host can start another poll right here.',
                        ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
