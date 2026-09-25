import 'dart:async';
import 'dart:convert';

import 'package:fastpoll/main.dart';
import 'package:fastpoll/models/poll_model.dart';
import 'package:fastpoll/screens/home_screen.dart';
import 'package:fastpoll/screens/host_screen.dart';
import 'package:fastpoll/screens/vote_screen.dart';
import 'package:fastpoll/screens/poll_results_screen.dart';
import 'package:fastpoll/widgets/room_loading_view.dart';
import 'package:fastpoll/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const session = RoomSession(
  roomCode: 'AB12',
  token: 'private-test-token',
  name: 'Alex',
);

class FakeRoomSocket extends RoomSocket {
  FakeRoomSocket() : super(session);
  final controller = StreamController<Map<String, dynamic>>();
  final votes = <int>[];
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  Future<void> connect() async {}
  @override
  void vote(String pollId, int option) {
    votes.add(option);
  }

  @override
  Future<void> close() async {
    await controller.close();
  }
}

Map<String, dynamic> state({
  bool host = false,
  String? pollId,
  int? selected,
  bool closed = false,
}) => {
  'event': 'STATE_UPDATE',
  'is_host': host,
  'is_open': true,
  'participants': [
    {'name': 'Alex', 'is_host': host, 'online': true},
  ],
  'poll': pollId == null
      ? null
      : {
          'id': pollId,
          'topic': 'Dinner?',
          'status': closed ? 'closed' : 'open',
          'time_left': closed ? 0 : 60,
          'selected_option': selected,
          'winner_ids': closed ? [0] : [],
          'options': [
            {'id': 0, 'text': 'Tacos', 'votes': selected == 0 ? 1 : 0},
            {'id': 1, 'text': 'Pizza', 'votes': 0},
          ],
        },
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home validates name and normalizes pasted room codes', (
    tester,
  ) async {
    // Keep the CI viewport when this suite also runs on a taller device.
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FastPollApp());
    expect(find.text('Create Room'), findsOneWidget);
    await tester.tap(find.text('Create Room'));
    await tester.pump();
    // Test fonts can wrap the form enough to leave this lazy child unbuilt.
    await tester.scrollUntilVisible(
      find.text('Enter your name first.'),
      150,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    expect(find.text('Enter your name first.'), findsOneWidget);
    final roomCode = find.widgetWithText(TextField, 'Room code');
    await tester.ensureVisible(roomCode);
    await tester.enterText(roomCode, ' ab-12 xyz');
    expect(tester.widget<TextField>(roomCode).controller!.text, 'AB12');
  });

  test('formatter handles deletion and mixed-case input', () {
    final formatter = RoomCodeFormatter();
    expect(
      formatter
          .formatEditUpdate(
            TextEditingValue.empty,
            const TextEditingValue(text: 'aB-1!2'),
          )
          .text,
      'AB12',
    );
    expect(
      formatter
          .formatEditUpdate(
            const TextEditingValue(text: 'AB12'),
            const TextEditingValue(text: 'AB1'),
          )
          .text,
      'AB1',
    );
  });

  test('join reuses saved token and retains host session', () async {
    await SessionStore.save(session);
    final api = ApiService(
      client: MockClient((request) async {
        expect(jsonDecode(request.body)['session_token'], session.token);
        expect(request.url.path, '/api/rooms/AB12/join');
        return http.Response(jsonEncode(session.toJson()), 200);
      }),
    );
    final progress = <String>[];
    final restored = await api.enter(
      name: 'Alex',
      code: 'AB12',
      onProgress: progress.add,
    );
    expect(progress, [
      'Checking your saved room session…',
      'Joining your room…',
      'Saving your place in the room…',
    ]);
    expect(restored.token, session.token);
    expect((await SessionStore.read('AB12'))!.token, session.token);
    api.close();
  });

  test(
    'invalid saved session is cleared without silently creating another voter',
    () async {
      await SessionStore.save(session);
      var requests = 0;
      final api = ApiService(
        client: MockClient((request) async {
          requests++;
          return http.Response('{"detail":"Session expired"}', 401);
        }),
      );
      await expectLater(
        api.enter(name: 'Alex', code: 'AB12'),
        throwsA(isA<ApiFailure>()),
      );
      expect(requests, 1);
      expect(await SessionStore.read('AB12'), isNull);
      api.close();
    },
  );

  testWidgets('guest lobby does not expose host controls', (tester) async {
    final socket = FakeRoomSocket();
    await tester.pumpWidget(
      MaterialApp(
        home: VoteScreen(session: session, socket: socket),
      ),
    );
    socket.controller.add(state());
    await tester.pump();
    expect(find.text('Waiting for the host to start a poll.'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Create poll'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('host lobby exposes join toggle and create poll', (tester) async {
    final socket = FakeRoomSocket();
    await tester.pumpWidget(
      MaterialApp(
        home: VoteScreen(session: session, socket: socket),
      ),
    );
    socket.controller.add(state(host: true));
    await tester.pump();
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.text('Create poll'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'vote waits for confirmation, reconnect disables controls, next poll resets',
    (tester) async {
      final socket = FakeRoomSocket();
      await tester.pumpWidget(
        MaterialApp(
          home: VoteScreen(session: session, socket: socket),
        ),
      );
      socket.controller.add(state(pollId: 'first'));
      await tester.pump();
      await tester.ensureVisible(find.text('Tacos'));
      await tester.tap(find.text('Tacos'));
      await tester.pump();
      expect(socket.votes, [0]);
      expect(find.text('Sending your vote…'), findsOneWidget);
      expect(find.text('Your vote is counted.'), findsNothing);
      socket.controller.add(state(pollId: 'first', selected: 0));
      await tester.pump();
      expect(find.text('Your vote is counted.'), findsNothing);
      final selectedButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('option-first-0')),
      );
      expect(selectedButton.onPressed, isNull);
      expect(
        selectedButton.style!.backgroundColor!.resolve({WidgetState.disabled}),
        isNotNull,
      );
      expect(find.text('Sending your vote…'), findsNothing);
      socket.controller.add({'event': 'CONNECTING'});
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(find.byType(OutlinedButton).first)
            .onPressed,
        isNull,
      );
      socket.controller.add(state(pollId: 'second'));
      await tester.pump();
      expect(find.text('Your vote is counted.'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byType(OutlinedButton).first)
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('templates remain editable and custom clears the draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: HostScreen(session: session)),
    );
    await tester.tap(find.text('Activities'));
    await tester.pump();
    expect(find.text('Pickleball'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), 'Tennis');
    expect(find.text('Tennis'), findsOneWidget);
    await tester.tap(find.text('Time'));
    await tester.pump();
    expect(find.text('When should we meet?'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(4));
    await tester.tap(find.text('Custom'));
    await tester.pump();
    expect(find.byType(TextFormField), findsNWidgets(3));
    for (final field in tester.widgetList<TextFormField>(
      find.byType(TextFormField),
    )) {
      expect(field.controller!.text, isEmpty);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('poll form validates empty inputs before calling server', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: HostScreen(session: session)),
    );
    await tester.ensureVisible(find.text('Start poll'));
    await tester.tap(find.text('Start poll'));
    await tester.pump();
    expect(find.text('Enter a topic'), findsOneWidget);
    expect(find.text('Enter an option'), findsNWidgets(2));
  });

  testWidgets(
    'loading explains slow connections and disappears on room state',
    (tester) async {
      final socket = FakeRoomSocket();
      await tester.pumpWidget(
        MaterialApp(
          home: VoteScreen(session: session, socket: socket),
        ),
      );
      expect(find.byType(RoomLoadingView), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      socket.controller.add({
        'event': 'CONNECTING',
        'message': 'Joining the live lobby…',
      });
      await tester.pump();
      expect(find.text('Joining the live lobby…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      expect(find.textContaining('Taking a little longer'), findsOneWidget);
      socket.controller.add(state());
      await tester.pump();
      expect(find.byType(RoomLoadingView), findsNothing);
      expect(
        find.text('Waiting for the host to start a poll.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'results are a separate screen and back does not reopen on heartbeat',
    (tester) async {
      final socket = FakeRoomSocket();
      await tester.pumpWidget(
        MaterialApp(
          home: VoteScreen(session: session, socket: socket),
        ),
      );
      socket.controller.add(state(host: true, pollId: 'first', selected: 0));
      await tester.pump();
      socket.controller.add(
        state(host: true, pollId: 'first', selected: 0, closed: true),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PollResultsScreen), findsOneWidget);
      expect(find.text('Winner: Tacos'), findsOneWidget);
      expect(find.text('You’re the host'), findsNothing);
      expect(find.text('Start another poll'), findsOneWidget);
      // Android back should reveal the lobby rather than leave the room.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PollResultsScreen), findsNothing);
      expect(find.text('View results'), findsOneWidget);
      socket.controller.add(
        state(host: true, pollId: 'first', selected: 0, closed: true),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PollResultsScreen), findsNothing);
      await tester.ensureVisible(find.text('View results'));
      await tester.tap(find.text('View results'));
      await tester.pumpAndSettle();
      expect(find.byType(PollResultsScreen), findsOneWidget);
      socket.controller.add(state(host: true, pollId: 'second'));
      await tester.pumpAndSettle();
      expect(find.byType(PollResultsScreen), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('option-second-0')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('guests see tie and no-vote results without host actions', (
    tester,
  ) async {
    final socket = FakeRoomSocket();
    await tester.pumpWidget(
      MaterialApp(
        home: VoteScreen(session: session, socket: socket),
      ),
    );
    final tied = state(pollId: 'tie', closed: true);
    (tied['poll'] as Map)['winner_ids'] = [0, 1];
    socket.controller.add(tied);
    await tester.pumpAndSettle();
    expect(find.text('It’s a tie: Tacos & Pizza'), findsOneWidget);
    expect(find.text('Start another poll'), findsNothing);
    final empty = state(pollId: 'empty', closed: true);
    (empty['poll'] as Map)['winner_ids'] = <int>[];
    socket.controller.add(empty);
    await tester.pumpAndSettle();
    expect(find.text('No votes this round'), findsOneWidget);
    socket.controller.add({'event': 'CONNECTING'});
    await tester.pumpAndSettle();
    expect(find.textContaining('Reconnecting to the room'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('results distinguish winner, tie, and no votes', () {
    final json =
        state(pollId: 'first', selected: 0, closed: true)['poll']
            as Map<String, dynamic>;
    expect(PollState.fromJson(json).result, 'Winner: Tacos');
    json['winner_ids'] = [0, 1];
    expect(PollState.fromJson(json).result, 'It’s a tie: Tacos & Pizza');
    json['winner_ids'] = <int>[];
    expect(PollState.fromJson(json).result, 'No votes this round');
  });
}
