import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:libresheets/services/pdf_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdfx/pdfx.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class TestPathProviderPlatform extends PathProviderPlatform {
  final String applicationDocumentsPath;
  final String applicationSupportPath;
  final String temporaryPath;

  TestPathProviderPlatform(
    String basePath, {
    String? applicationDocumentsPath,
    String? applicationSupportPath,
    String? temporaryPath,
  }) : applicationDocumentsPath = applicationDocumentsPath ?? basePath,
       applicationSupportPath = applicationSupportPath ?? basePath,
       temporaryPath = temporaryPath ?? basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      applicationDocumentsPath;

  @override
  Future<String?> getApplicationSupportPath() async => applicationSupportPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;
}

class TestWakelockPlatform extends WakelockPlusPlatformInterface {
  bool _enabled = false;

  @override
  Future<bool> get enabled async => _enabled;

  @override
  Future<void> toggle({required bool enable}) async {
    _enabled = enable;
  }
}

Future<Directory> createTestDirectory(String name) async {
  final directory = Directory(
    p.join(
      Directory.current.path,
      'build',
      'test_tmp',
      name,
      DateTime.now().microsecondsSinceEpoch.toString(),
    ),
  );
  await directory.create(recursive: true);
  return directory;
}

class FakePdfPageSource extends ChangeNotifier implements PdfPageSource {
  final Map<int, ui.Image> _images;

  FakePdfPageSource(this._images);

  @override
  Future<void> close() async {
    for (final image in _images.values) {
      image.dispose();
    }
  }

  @override
  ui.Image? getPage(int pageNumber) => _images[pageNumber];

  @override
  int get pageCount => _images.length;

  @override
  void requestPages(int currentPage) {}
}

Future<FakePdfPageSource> createFakePdfPageSource(int pageCount) async {
  final images = <int, ui.Image>{};
  for (int page = 1; page <= pageCount; page++) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final rect = ui.Rect.fromLTWH(0, 0, 80, 120);
    final color = Colors.primaries[(page - 1) % Colors.primaries.length];
    canvas.drawRect(rect, ui.Paint()..color = color.shade300);
    final picture = recorder.endRecording();
    images[page] = await picture.toImage(80, 120);
  }
  return FakePdfPageSource(images);
}

class FakePdfDocument extends PdfDocument {
  final Map<int, Uint8List> _pageBytes = {};

  FakePdfDocument({required int pageCount})
    : super(sourceName: 'fake.pdf', id: 'fake-document', pagesCount: pageCount);

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<PdfPage> getPage(
    int pageNumber, {
    bool autoCloseAndroid = false,
  }) async {
    return FakePdfPage(
      document: this,
      pageNumber: pageNumber,
      bytesLoader: () => _loadPageBytes(pageNumber),
      autoCloseAndroid: autoCloseAndroid,
    );
  }

  Future<Uint8List> _loadPageBytes(int pageNumber) async {
    final cachedBytes = _pageBytes[pageNumber];
    if (cachedBytes != null) {
      return cachedBytes;
    }
    final color = Colors.primaries[(pageNumber - 1) % Colors.primaries.length];
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final rect = ui.Rect.fromLTWH(0, 0, 80, 120);
    canvas.drawRect(rect, ui.Paint()..color = color.shade300);
    canvas.drawRect(
      ui.Rect.fromLTWH(8, 8, 64, 104),
      ui.Paint()..color = Colors.white,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(80, 120);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final bytes = byteData!.buffer.asUint8List();
    _pageBytes[pageNumber] = bytes;
    return bytes;
  }

  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => Object.hash(id, pagesCount);
}

class FakePdfPage extends PdfPage {
  final Future<Uint8List> Function() bytesLoader;

  FakePdfPage({
    required FakePdfDocument document,
    required int pageNumber,
    required this.bytesLoader,
    required bool autoCloseAndroid,
  }) : super(
         document: document,
         id: 'page-$pageNumber',
         pageNumber: pageNumber,
         width: 80,
         height: 120,
         autoCloseAndroid: autoCloseAndroid,
       );

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<PdfPageTexture> createTexture() {
    throw UnimplementedError();
  }

  @override
  Future<PdfPageImage?> render({
    required double width,
    required double height,
    PdfPageImageFormat format = PdfPageImageFormat.jpeg,
    String? backgroundColor,
    ui.Rect? cropRect,
    int quality = 100,
    bool forPrint = false,
    bool removeTempFile = true,
  }) async {
    return FakePdfPageImage(
      id: 'image-$pageNumber',
      pageNumber: pageNumber,
      width: width.round(),
      height: height.round(),
      bytes: await bytesLoader(),
      format: format,
      quality: quality,
    );
  }

  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => Object.hash(pageNumber, id);
}

class FakePdfPageImage extends PdfPageImage {
  const FakePdfPageImage({
    required super.id,
    required super.pageNumber,
    required super.width,
    required super.height,
    required super.bytes,
    required super.format,
    required super.quality,
  });

  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => Object.hash(pageNumber, id);
}
