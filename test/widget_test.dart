import 'package:flutter_test/flutter_test.dart';

import 'package:mitra/main.dart';

void main() {
  testWidgets('role selection screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const ElderlyCareApp());

    expect(find.text('Select Role'), findsOneWidget);
    expect(find.text('Elder'), findsOneWidget);
    expect(find.text('Caregiver'), findsOneWidget);
  });
}
