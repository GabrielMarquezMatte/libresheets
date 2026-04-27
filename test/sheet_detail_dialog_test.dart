import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libresheets/models/sheet.dart';
import 'package:libresheets/screens/sheet_detail_dialog.dart';

void main() {
  testWidgets('save clears optional metadata fields', (tester) async {
    final now = DateTime(2026, 4, 21);
    final sheet = Sheet(
      name: 'Fugue',
      path: 'C:/scores/fugue.pdf',
      composer: 'Bach',
      key: 'D minor',
      notes: 'Practice slowly',
      lastOpened: now,
      createdAt: now,
    );
    Sheet? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                saved = await showDialog<Sheet>(
                  context: context,
                  builder: (_) => SheetDetailDialog(sheet: sheet),
                );
              },
              child: const Text('Edit'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(8));

    await tester.enterText(fields.at(1), '');
    await tester.enterText(fields.at(5), '');
    await tester.enterText(fields.at(7), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.composer, isNull);
    expect(saved!.key, isNull);
    expect(saved!.notes, isNull);
  });
}
