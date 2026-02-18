import 'package:flutter_test/flutter_test.dart';

import 'package:libresheets/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LibreSheetsApp());
    expect(find.text('LibreSheets'), findsOneWidget);
  });
}
