import 'package:flutter_test/flutter_test.dart';
import 'package:blood/main.dart';

void main() {
  testWidgets(
    'eDonate app starts successfully',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MyApp(isLoggedIn: false),
      );

      expect(find.byType(MyApp), findsOneWidget);
    },
  );
}