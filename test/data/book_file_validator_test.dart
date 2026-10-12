import 'dart:io';
import 'package:archive/archive.dart';
import '../support/pdfium_test_setup.dart';
import '../support/valid_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ereader/data/services/book_file_validator.dart';

void main() {
  late Directory temp;
  setUpAll(initializeTestPdfium);
  setUp(
    () async =>
        temp = await Directory.systemTemp.createTemp('book-validation-'),
  );
  tearDown(() async => temp.delete(recursive: true));

  test('rejects HTML masquerading as a PDF', () async {
    final file = await File(
      '${temp.path}/book.pdf',
    ).writeAsString('<html>Sign in</html>');
    await expectLater(
      BookFileValidator.validate(file, 'pdf'),
      throwsFormatException,
    );
  });
  test('rejects truncated PDF', () async {
    final file = await File(
      '${temp.path}/book.pdf',
    ).writeAsString('%PDF-1.7\ntruncated');
    await expectLater(
      BookFileValidator.validate(file, 'pdf'),
      throwsFormatException,
    );
  });
  test('rejects marker-only PDF with no readable document', () async {
    final file = await File(
      '${temp.path}/book.pdf',
    ).writeAsString('%PDF-1.7\nnot a PDF\n%%EOF');
    await expectLater(
      BookFileValidator.validate(file, 'pdf'),
      throwsFormatException,
    );
  });
  test('accepts a readable PDF with one page', () async {
    final file = await File('${temp.path}/book.pdf').writeAsString(validPdf());
    await BookFileValidator.validate(file, 'pdf');
  });
  test('rejects a ZIP which is not an EPUB', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('readme.txt', 'not an epub'));
    final file = await File(
      '${temp.path}/book.epub',
    ).writeAsBytes(ZipEncoder().encode(archive));
    await expectLater(
      BookFileValidator.validate(file, 'epub'),
      throwsFormatException,
    );
  });
  test('accepts EPUB with mimetype, container and package', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/chapter.xhtml',
          '<html><body>Chapter</body></html>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/content.opf',
          '<package><manifest><item id="c1" href="chapter.xhtml"/></manifest><spine><itemref idref="c1"/></spine></package>',
        ),
      );
    final file = await File(
      '${temp.path}/book.epub',
    ).writeAsBytes(ZipEncoder().encode(archive));
    await BookFileValidator.validate(file, 'epub');
    expect(await file.exists(), isTrue);
  });
  test('accepts escaped chapter paths in EPUB manifests', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<container><rootfile full-path="OEBPS/book.opf"/></container>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/book.opf',
          '<package><manifest><item id="c1" href="Chapter%201.xhtml"/></manifest>'
              '<spine><itemref idref="c1"/></spine></package>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/Chapter 1.xhtml',
          '<html><body>Chapter</body></html>',
        ),
      );
    final file = await File(
      '${temp.path}/book.epub',
    ).writeAsBytes(ZipEncoder().encode(archive));
    await BookFileValidator.validate(file, 'epub');
  });
  test('rejects EPUB with a package but no readable chapters', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<container><rootfile full-path="book.opf"/></container>',
        ),
      )
      ..addFile(ArchiveFile.string('book.opf', '<package/>'));
    final file = await File(
      '${temp.path}/book.epub',
    ).writeAsBytes(ZipEncoder().encode(archive));
    await expectLater(
      BookFileValidator.validate(file, 'epub'),
      throwsFormatException,
    );
  });
  test('rejects unsupported formats', () async {
    final file = await File('${temp.path}/book.cbz').writeAsString('test');
    await expectLater(
      BookFileValidator.validate(file, 'cbz'),
      throwsFormatException,
    );
  });
}
