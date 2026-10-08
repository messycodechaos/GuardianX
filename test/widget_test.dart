import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_x/main.dart';

void main() {
  testWidgets('GuardianXApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame using the real root class:
    await tester.pumpWidget(const GuardianXApp());
  });
}