import 'package:fastpoll/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home screen offers create and join actions', (tester) async {
    await tester.pumpWidget(const FastPollApp());

    expect(find.text('FastPoll'), findsOneWidget);
    expect(find.text('Create Poll'), findsOneWidget);
    expect(find.text('Join Room'), findsOneWidget);
  });
}
