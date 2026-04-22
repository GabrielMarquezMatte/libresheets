import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> importPdf(String sourcePath) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final sheetsDir = Directory(p.join(docsDir.path, 'sheets'));
  await sheetsDir.create(recursive: true);

  if (p.isWithin(sheetsDir.path, sourcePath)) {
    return sourcePath;
  }

  final source = File(sourcePath);
  final stream = source.openRead();
  final digest = await sha1.bind(stream).first;
  final destPath = p.join(sheetsDir.path, '$digest.pdf');

  final dest = File(destPath);
  if (await dest.exists()) {
    return destPath;
  }

  await source.copy(destPath);
  return destPath;
}
