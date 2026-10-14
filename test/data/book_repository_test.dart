import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ereader/data/models/book_model.dart';
import 'package:ereader/data/repositories/book_repository.dart';
import 'package:ereader/data/models/store_book.dart';

// Writes the exact pre-upgrade field schema (0..14, with no catalog ID).
class LegacyBookAdapter extends BookModelAdapter {
  @override
  void write(BinaryWriter writer, BookModel book) {
    final fields = [
      book.id,
      book.title,
      book.author,
      book.coverUrl,
      book.localCoverPath,
      book.localPath,
      book.format,
      book.totalPages,
      book.lastReadPage,
      book.lastReadProgress,
      book.lastReadCfi,
      book.lastReadTime,
      book.addedTime,
      book.md5,
      book.fileSize,
    ];
    writer.writeByte(fields.length);
    for (var index = 0; index < fields.length; index++) {
      writer
        ..writeByte(index)
        ..write(fields[index]);
    }
  }
}

void main() {
  late Directory temp;
  late Box<BookModel> box;
  late BookRepository repository;
  setUpAll(() => Hive.registerAdapter(BookModelAdapter()));
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('library-test-');
    Hive.init(temp.path);
    box = await Hive.openBox<BookModel>('books');
    repository = BookRepository(booksBox: box);
  });
  tearDown(() async {
    await box.close();
    await temp.delete(recursive: true);
  });
  test(
    'old Hive libraries reopen without losing books or reading positions',
    () async {
      await box.close();
      Hive.registerAdapter(LegacyBookAdapter(), override: true);
      box = await Hive.openBox<BookModel>('books');
      await box.put(
        'old',
        BookModel(
          id: 'old',
          title: 'Existing book',
          author: 'Author',
          localPath: 'existing.epub',
          format: 'epub',
          lastReadPage: 5,
          lastReadProgress: 0.42,
          lastReadCfi: 'epubcfi(/6/2)',
          totalPages: 100,
        ),
      );
      await box.close();
      Hive.registerAdapter(BookModelAdapter(), override: true);
      box = await Hive.openBox<BookModel>('books');
      final restored = box.get('old')!;
      expect(restored.title, 'Existing book');
      expect(restored.lastReadPage, 5);
      expect(restored.lastReadProgress, 0.42);
      expect(restored.lastReadCfi, 'epubcfi(/6/2)');
      expect(restored.totalPages, 100);
      expect(restored.storeBookId, isNull);
    },
  );
  test(
    'queued checkpoints remain coherent after reopening the library',
    () async {
      await box.put(
        'checkpoint',
        BookModel(
          id: 'checkpoint',
          title: 'Checkpoint',
          author: 'Author',
          localPath: 'book.epub',
          format: 'epub',
        ),
      );
      final other = BookRepository(booksBox: box);
      final writes = [
        repository.updateReadingProgress(
          bookId: 'checkpoint',
          page: 0,
          progress: 0.3,
          cfi: 'epubcfi(/6/2)',
          epubViewport: {
            'offset': -8.0,
            'layout': {'fontSize': '18px'},
          },
        ),
        other.updateReadingProgress(
          bookId: 'checkpoint',
          page: 0,
          progress: 0.7,
          cfi: 'epubcfi(/6/4)',
          epubViewport: {
            'offset': -15.0,
            'layout': {'fontSize': '20px'},
          },
        ),
      ];
      await Future.wait(writes);
      await box.close();
      box = await Hive.openBox<BookModel>('books');
      final saved = box.get('checkpoint')!;
      expect(saved.lastReadCfi, 'epubcfi(/6/4)');
      expect(saved.lastReadProgress, 0.7);
      expect(saved.epubCheckpoint, {
        'version': 1,
        'revision': 2,
        'cfi': 'epubcfi(/6/4)',
        'progress': 0.7,
        'offset': -15.0,
        'layout': {'fontSize': '20px'},
      });
    },
  );

  test(
    'imports preserve Unicode EPUB metadata and cannot overwrite same-name books',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
        ..addFile(
          ArchiveFile.string(
            'META-INF/container.xml',
            '<container><rootfile full-path="book.opf"/></container>',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'book.opf',
            '<package xmlns:dc="http://purl.org/dc/elements/1.1/">'
                '<metadata><dc:title>Les Misérables</dc:title><dc:creator>Victor Hugo</dc:creator></metadata><manifest><item id="c1" href="chapter.xhtml"/></manifest><spine><itemref idref="c1"/></spine></package>',
          ),
        );
      archive.addFile(
        ArchiveFile.string(
          'chapter.xhtml',
          '<html><body>Chapter</body></html>',
        ),
      );
      final source = await File(
        '${temp.path}/same.epub',
      ).writeAsBytes(ZipEncoder().encode(archive));
      final first = await repository.importBookFile(
        source,
        Directory('${temp.path}/managed'),
      );
      final second = await repository.importBookFile(
        source,
        Directory('${temp.path}/managed'),
      );
      expect(first.title, 'Les Misérables');
      expect(first.author, 'Victor Hugo');
      expect(first.localPath, isNot(second.localPath));
      await repository.deleteBook(second.id);
      expect(await File(first.localPath).exists(), isTrue);
    },
  );
  test('rejects invalid imports without creating a library entry', () async {
    final source = await File(
      '${temp.path}/bad.epub',
    ).writeAsString('<html>Error</html>');
    await expectLater(
      repository.importBookFile(source, Directory('${temp.path}/managed')),
      throwsFormatException,
    );
    expect(box.values, isEmpty);
  });
  test(
    'different hashes identify distinct editions with identical metadata',
    () async {
      await box.put(
        'existing',
        BookModel(
          id: 'existing',
          title: 'Same',
          author: 'Author',
          localPath: 'file',
          format: 'pdf',
          md5: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      );
      expect(
        repository.findStoreBook(
          const UnifiedBook(
            title: 'Same',
            author: 'Author',
            extension: 'pdf',
            source: BookSource.annasArchive,
            md5: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          ),
        ),
        isNull,
      );
      expect(
        repository.findStoreBook(
          const UnifiedBook(
            title: 'Same',
            author: 'Author',
            extension: 'pdf',
            source: BookSource.annasArchive,
            md5: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
        ),
        isNotNull,
      );
    },
  );
  test('progress clamps invalid values and persists total PDF pages', () async {
    final book = BookModel(
      id: 'book',
      title: 'Title',
      author: 'Author',
      localPath: 'file',
      format: 'pdf',
    );
    await box.put(book.id, book);
    await repository.updateReadingProgress(
      bookId: book.id,
      page: 3,
      progress: 1.7,
      totalPages: 30,
    );
    expect(book.lastReadProgress, 1);
    expect(book.totalPages, 30);
    await box.close();
    box = await Hive.openBox<BookModel>('books');
    expect(box.get('book')!.totalPages, 30);
  });
}
