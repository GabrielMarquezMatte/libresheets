import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _managedPdfPrefix = 'managed:';
final _managedPdfNamePattern = RegExp(r'^[a-f0-9]{40}\.pdf$');

String normalizeStoredPdfPath(String path) {
  if (path.startsWith(_managedPdfPrefix)) {
    return path;
  }
  if (_isLegacyManagedAbsolutePath(path)) {
    return '$_managedPdfPrefix${p.basename(path)}';
  }
  return p.canonicalize(path);
}

Future<String> resolvePdfPath(String storedPath) async {
  final managedFileName = _managedPdfFileName(storedPath);
  if (managedFileName == null) {
    return p.canonicalize(storedPath);
  }
  final currentManagedPath = await _managedPdfAbsolutePath(managedFileName);
  final currentManagedFile = File(currentManagedPath);
  if (await currentManagedFile.exists()) {
    return currentManagedPath;
  }
  final legacyCandidates = await _legacyManagedPdfCandidates(
    managedFileName,
    storedPath,
  );
  for (final legacyPath in legacyCandidates) {
    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) {
      continue;
    }
    await legacyFile.copy(currentManagedPath);
    return currentManagedPath;
  }
  return currentManagedPath;
}

Future<String> importPdf(String sourcePath) async {
  if (sourcePath.startsWith(_managedPdfPrefix)) {
    return sourcePath;
  }
  final canonicalSourcePath = p.canonicalize(sourcePath);
  final managedFileName = _managedPdfFileName(canonicalSourcePath);
  if (managedFileName != null &&
      await _isCurrentManagedPath(canonicalSourcePath)) {
    return '$_managedPdfPrefix$managedFileName';
  }
  final source = File(canonicalSourcePath);
  final stream = source.openRead();
  final digest = await sha1.bind(stream).first;
  final fileName = '$digest.pdf';
  final storedPath = '$_managedPdfPrefix$fileName';
  final destPath = await _managedPdfAbsolutePath(fileName);
  final dest = File(destPath);
  if (await dest.exists()) {
    return storedPath;
  }

  await source.copy(destPath);
  return storedPath;
}

String? _managedPdfFileName(String storedPath) {
  if (storedPath.startsWith(_managedPdfPrefix)) {
    return storedPath.substring(_managedPdfPrefix.length);
  }
  if (_isLegacyManagedAbsolutePath(storedPath)) {
    return p.basename(storedPath);
  }
  return null;
}

Future<String> _managedPdfAbsolutePath(String fileName) async {
  final dir = await _managedSheetsDirectory();
  return p.join(dir.path, fileName);
}

Future<Directory> _managedSheetsDirectory() async {
  final supportDir = await getApplicationSupportDirectory();
  final sheetsDir = Directory(p.join(supportDir.path, 'sheets'));
  await sheetsDir.create(recursive: true);
  return sheetsDir;
}

Future<bool> _isCurrentManagedPath(String absolutePath) async {
  final supportDir = await _managedSheetsDirectory();
  if (p.isWithin(supportDir.path, absolutePath)) {
    return true;
  }
  final docsDir = await getApplicationDocumentsDirectory();
  return p.isWithin(p.join(docsDir.path, 'sheets'), absolutePath);
}

bool _isLegacyManagedAbsolutePath(String path) {
  if (!p.isAbsolute(path)) {
    return false;
  }
  if (p.basename(p.dirname(path)) != 'sheets') {
    return false;
  }
  return _managedPdfNamePattern.hasMatch(p.basename(path));
}

Future<List<String>> _legacyManagedPdfCandidates(
  String fileName,
  String storedPath,
) async {
  final candidates = <String>{};
  final docsDir = await getApplicationDocumentsDirectory();
  candidates.add(p.join(docsDir.path, 'sheets', fileName));
  if (!storedPath.startsWith(_managedPdfPrefix)) {
    candidates.add(p.canonicalize(storedPath));
  }
  return candidates.toList();
}
