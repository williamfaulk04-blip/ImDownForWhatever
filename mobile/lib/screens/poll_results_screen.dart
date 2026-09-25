import 'package:flutter/material.dart';

import '../models/poll_model.dart';

/// A separate presentation driven by the room's server snapshot. The room
/// coordinator keeps its socket alive so a new poll replaces these results.
class PollResultsScreen extends StatelessWidget {
  const PollResultsScreen({
    required this.roomCode,
    required this.poll,
    required this.isHost,
    required this.connected,
    required this.onBack,
    required this.onNextPoll,
    this.error,
    super.key,
  });
  final String roomCode;
  final PollState poll;
  final bool isHost;
  final bool connected;
  final VoidCallback onBack;
  final VoidCallback? onNextPoll;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasWinner = poll.winnerIds.length == 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Poll results'),
        leading: IconButton(
          tooltip: 'Back to lobby',
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'ROOM $roomCode',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 24),
              CircleAvatar(
                radius: 48,
                backgroundColor: colors.primaryContainer,
                child: Icon(
                  hasWinner
                      ? Icons.emoji_events_rounded
                      : poll.winnerIds.isEmpty
                      ? Icons.how_to_vote_outlined
                      : Icons.handshake_outlined,
                  size: 52,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                hasWinner
                    ? 'We have a winner!'
                    : poll.winnerIds.isEmpty
                    ? 'Maybe next round?'
                    : 'Too close to call!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                poll.result,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Text(
                poll.topic,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${poll.totalVotes} ${poll.totalVotes == 1 ? 'vote' : 'votes'} cast · Poll finished',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              ...poll.options.map(
                (option) => Card(
                  color: poll.winnerIds.contains(option.id)
                      ? colors.primaryContainer
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            if (poll.winnerIds.contains(option.id))
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(Icons.star_rounded, size: 20),
                              ),
                            Expanded(
                              child: Text(
                                option.text,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              '${option.votes} ${option.votes == 1 ? 'vote' : 'votes'}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: poll.totalVotes == 0
                              ? 0
                              : option.votes / poll.totalVotes,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (!connected)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Reconnecting to the room… Waiting for the next room update.',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(error!, style: TextStyle(color: colors.error)),
                ),
              if (isHost)
                FilledButton.icon(
                  onPressed: onNextPoll,
                  icon: const Icon(Icons.add_chart),
                  label: const Text('Start another poll'),
                )
              else
                const Text(
                  'Waiting for the host’s next poll. You’ll join it automatically.',
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 8),
              TextButton(onPressed: onBack, child: const Text('Back to lobby')),
            ],
          ),
        ),
      ),
    );
  }
}
