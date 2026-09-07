import 'package:flutter_test/flutter_test.dart';
import 'package:grovio_supermart/main.dart';

void main() {
  testWidgets('App load smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const GrovioCustomerApp());

    // Verify that the Grovio brand name appears
    expect(find.text('GROVIO'), findsOneWidget);
  });
}
