// Run the same behavior checks on an Android device when a host tester is unavailable.
import 'package:integration_test/integration_test.dart';

import '../test/widget_test.dart' as suite;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suite.main();
}
