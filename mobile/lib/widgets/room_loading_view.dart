import 'dart:async';

import 'package:flutter/material.dart';

/// Status follows completed/requested operations; the bar deliberately has no
/// percentage because connection duration cannot be estimated honestly.
class RoomLoadingView extends StatefulWidget {
  const RoomLoadingView({required this.status, super.key});
  final String status;
  @override
  State<RoomLoadingView> createState() => _RoomLoadingViewState();
}

class _RoomLoadingViewState extends State<RoomLoadingView> {
  Timer? _timer;
  bool _takingLonger = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _takingLonger = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      child: Icon(
                        Icons.groups_rounded,
                        size: 56,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Getting everyone together',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your next plan starts here.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Semantics(
            liveRegion: true,
            child: Text(
              widget.status,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 16),
          const LinearProgressIndicator(
            minHeight: 6,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          const SizedBox(height: 16),
          Text(
            _takingLonger
                ? 'Taking a little longer than usual. Still waiting for a connection—keep this screen open.'
                : 'Connecting you to your friends…',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}
