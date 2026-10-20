import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blood/main.dart';

void main() {
  testWidgets(
    'eDonate app starts successfully',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MyApp(isLoggedIn: false),
      );

      expect(find.byType(MyApp), findsOneWidget);

      // The splash screen schedules its own timers: let them run out after the
      // app is torn down, as every other screen test does.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    },
  );
}
