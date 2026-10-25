import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledgerly/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Ledgerly starts with a clean empty workspace', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const LedgerlyApp());
    await tester.pumpAndSettle();
    expect(find.text('Business overview'), findsOneWidget);
    expect(find.text('Your workspace is ready'), findsOneWidget);
    expect(find.text('Northstar Studio'), findsNothing);
  });
}
