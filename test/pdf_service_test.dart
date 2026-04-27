import 'package:flutter_test/flutter_test.dart';
import 'package:libresheets/services/pdf_service.dart';

import 'test_support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('close is idempotent', () async {
    final document = FakePdfDocument(pageCount: 1);
    final service = PdfService(document);

    await service.close();
    await service.close();

    expect(document.closeCount, 1);
    expect(document.isClosed, isTrue);
  });
}
