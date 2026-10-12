import 'dart:io';
import 'package:pdfrx/pdfrx.dart';

// Flutter tests do not load the platform app's PDFium library. Use the native
// library already bundled by the dependency's build hook, with no test download.
Future<void> initializeTestPdfium() async {
  final root = Directory('.dart_tool/hooks_runner/shared/pdfium_dart/build');
  final suffix = Platform.isMacOS
      ? 'libpdfium.dylib'
      : Platform.isWindows
      ? 'pdfium.dll'
      : 'libpdfium.so';
  final modules = await root
      .list(recursive: true)
      .where((entry) => entry is File && entry.path.endsWith(suffix))
      .toList();
  if (modules.isEmpty) {
    throw StateError(
      'PDFium build-hook library not found. Run flutter pub get and flutter test.',
    );
  }
  Pdfrx.pdfiumModulePath = modules.first.absolute.path;
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  await pdfrxFlutterInitialize();
}
