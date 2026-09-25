// Requires the FastAPI server on the emulator host at port 8000.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:fastpoll/models/poll_model.dart';

import 'package:fastpoll/main.dart';
import 'package:fastpoll/screens/vote_screen.dart';
import 'package:fastpoll/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
  }
  fail('Room did not reach the expected state within eight seconds');
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real server: repeat polls, reconnect, and automatic results', (
    tester,
  ) async {
    RoomSocket? guest;
    StreamSubscription<Map<String, dynamic>>? subscription;
    Map<String, dynamic>? guestState;
    try {
      await tester.pumpWidget(const FastPollApp());
      await tester.enterText(find.byType(TextField).first, 'QA Host');
      await tapText(tester, 'Create Room');
      await waitFor(
        tester,
        () =>
            find.byType(VoteScreen).evaluate().isNotEmpty &&
            find.text('You’re the host').evaluate().isNotEmpty,
      );
      final host = tester.widget<VoteScreen>(find.byType(VoteScreen)).session;
      // A second installation has no saved host token. Use a fresh join request.
      final joined = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/rooms/${host.roomCode}/join'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'QA Friend'}),
      );
      expect(joined.statusCode, 200);
      final friend = RoomSession.fromJson(
        jsonDecode(joined.body) as Map<String, dynamic>,
      );
      guest = RoomSocket(friend);
      subscription = guest.events.listen((event) {
        if (event['event'] == 'STATE_UPDATE') guestState = event;
      });
      await guest.connect();
      await waitFor(
        tester,
        () =>
            guestState != null && find.text('QA Friend').evaluate().isNotEmpty,
      );
      expect(guestState!['is_host'], false);

      final toggle = find.byType(SwitchListTile);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await waitFor(tester, () => guestState!['is_open'] == false);
      final rejected = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/rooms/${host.roomCode}/join'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'Late friend'}),
      );
      expect(rejected.statusCode, 403);

      await tapText(tester, 'Create poll');
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'What should we do?',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'Games');
      await tester.enterText(find.byType(TextFormField).at(2), 'Food');
      await tapText(tester, 'Start poll');
      await waitFor(
        tester,
        () =>
            guestState!['poll'] != null &&
            find.text('Games').evaluate().isNotEmpty,
      );
      final first = guestState!['poll'] as Map<String, dynamic>;
      guest.vote(first['id'] as String, 0);
      await waitFor(
        tester,
        () => (guestState!['poll'] as Map)['selected_option'] == 0,
      );
      await tapText(tester, 'Games');
      await waitFor(
        tester,
        () => (guestState!['poll'] as Map)['options'][0]['votes'] == 2,
      );
      await tapText(tester, 'End poll and show result');
      await waitFor(
        tester,
        () => (guestState!['poll'] as Map)['status'] == 'closed',
      );
      await tester.pumpAndSettle();
      expect(find.text('Your vote is counted.'), findsNothing);
      expect(find.text('Poll results'), findsOneWidget);
      expect(find.text('Winner: Games'), findsOneWidget);
      expect((guestState!['poll'] as Map)['options'][0]['votes'], 2);

      await tapText(tester, 'Start another poll');
      await tester.enterText(find.byType(TextFormField).at(0), 'Which game?');
      await tester.enterText(find.byType(TextFormField).at(1), 'Mario Kart');
      await tester.enterText(find.byType(TextFormField).at(2), 'Minecraft');
      await tapText(tester, 'Start poll');
      await waitFor(
        tester,
        () => (guestState!['poll'] as Map)['id'] != first['id'],
      );
      expect((guestState!['poll'] as Map)['selected_option'], isNull);
      expect(
        tester.widget<VoteScreen>(find.byType(VoteScreen)).session.roomCode,
        host.roomCode,
      );
      guest.vote((guestState!['poll'] as Map)['id'] as String, 1);
      await waitFor(
        tester,
        () => (guestState!['poll'] as Map)['selected_option'] == 1,
      );

      await subscription.cancel();
      await guest.close();
      guest = RoomSocket(friend);
      guestState = null;
      subscription = guest.events.listen((event) {
        if (event['event'] == 'STATE_UPDATE') guestState = event;
      });
      await guest.connect();
      await waitFor(tester, () => guestState != null);
      expect((guestState!['poll'] as Map)['selected_option'], 1);
      expect(guestState!['is_open'], false);

      // Both manual ending and natural expiration must switch the host UI.
      final secondId = (guestState!['poll'] as Map)['id'];
      final authHeaders = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${host.token}',
      };
      final ended = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/rooms/${host.roomCode}/polls/$secondId/close',
        ),
        headers: authHeaders,
      );
      expect(ended.statusCode, 200);
      final timed = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/rooms/${host.roomCode}/polls'),
        headers: authHeaders,
        body: jsonEncode({
          'topic': 'Quick round',
          'options': ['Walk', 'Movie'],
          'duration': 1,
        }),
      );
      expect(timed.statusCode, 201);
      final timedId = (jsonDecode(timed.body)['poll'] as Map)['id'];
      await waitFor(
        tester,
        () =>
            (guestState!['poll'] as Map)['id'] == timedId &&
            (guestState!['poll'] as Map)['status'] == 'closed' &&
            find.text('No votes this round').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.text('Poll results'), findsOneWidget);
      expect(find.text('No votes this round'), findsOneWidget);
    } finally {
      await subscription?.cancel();
      await guest?.close();
      await tester.pumpWidget(const SizedBox());
    }
  });
}
