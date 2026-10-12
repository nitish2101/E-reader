import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:pdfrx/pdfrx.dart';

class BookFileValidator {
  static const maxFileBytes = 300 * 1024 * 1024;

  static Future<void> validate(File file, String format) async {
    final length = await file.length();
    if (length == 0 || length > maxFileBytes) {
      throw const FormatException(
        'The book is empty or exceeds the 300 MB limit.',
      );
    }
    if (format == 'pdf') {
      final reader = await file.open();
      try {
        final header = latin1.decode(
          await reader.read(length < 1024 ? length : 1024),
        );
        await reader.setPosition(length > 2048 ? length - 2048 : 0);
        final tail = latin1.decode(await reader.read(2048));
        if (!header.contains('%PDF-') || !tail.contains('%%EOF')) {
          throw const FormatException(
            'This download is not a complete PDF book.',
          );
        }
      } finally {
        await reader.close();
      }
      try {
        await pdfrxFlutterInitialize();
        final document = await PdfDocument.openFile(file.path);
        try {
          if (document.pages.isEmpty) {
            throw const FormatException('This PDF has no readable pages.');
          }
        } finally {
          await document.dispose();
        }
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException(
          'This PDF is damaged or requires a password.',
        );
      }
    } else if (format == 'epub') {
      final input = InputFileStream(file.path);
      try {
        final archive = ZipDecoder().decodeStream(input);
        final mimetype = archive.findFile('mimetype');
        final container = archive.findFile('META-INF/container.xml');
        if (mimetype == null ||
            mimetype.size > 100 ||
            utf8.decode(mimetype.content).trim() != 'application/epub+zip' ||
            container == null ||
            container.size > 1024 * 1024) {
          throw const FormatException('This download is not an EPUB book.');
        }
        final xml = XmlDocument.parse(utf8.decode(container.content));
        final roots = xml.findAllElements('rootfile');
        final packagePath = roots.isEmpty
            ? null
            : roots.first.getAttribute('full-path');
        final package = packagePath == null
            ? null
            : archive.findFile(packagePath);
        if (package == null || package.size > 2 * 1024 * 1024) {
          throw const FormatException(
            'The EPUB package is missing or incomplete.',
          );
        }
        final opf = XmlDocument.parse(utf8.decode(package.content));
        final elements = opf.descendants.whereType<XmlElement>().toList();
        final spine = elements.where((e) => e.name.local == 'spine');
        final manifest = elements.where((e) => e.name.local == 'manifest');
        if (opf.rootElement.name.local != 'package' ||
            spine.isEmpty ||
            manifest.isEmpty) {
          throw const FormatException(
            'The EPUB has no readable book structure.',
          );
        }
        final items = <String, String>{
          for (final item in manifest.first.childElements)
            if (item.name.local == 'item' &&
                item.getAttribute('id') != null &&
                item.getAttribute('href') != null)
              item.getAttribute('id')!: item.getAttribute('href')!,
        };
        final chapters = spine.first.childElements.where(
          (e) => e.name.local == 'itemref',
        );
        if (chapters.isEmpty) {
          throw const FormatException('The EPUB has no readable chapters.');
        }
        for (final chapter in chapters) {
          final href = items[chapter.getAttribute('idref')];
          if (href == null ||
              archive.findFile(
                    Uri.decodeComponent(
                      Uri.parse(packagePath!).resolve(href).path,
                    ),
                  ) ==
                  null) {
            throw const FormatException(
              'An EPUB chapter is missing or incomplete.',
            );
          }
        }
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException('The EPUB file is corrupt or incomplete.');
      } finally {
        await input.close();
      }
    } else {
      throw const FormatException('Only PDF and EPUB books are supported.');
    }
  }
}
