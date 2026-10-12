import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:pdfrx/pdfrx.dart';
import 'dart:ui' as ui;

import '../models/book_model.dart';
import '../../core/constants/app_constants.dart';
import '../models/store_book.dart';
import '../services/book_file_validator.dart';

class BookRepository {
  final Box<BookModel> _booksBox;
  BookRepository({Box<BookModel>? booksBox})
    : _booksBox = booksBox ?? Hive.box<BookModel>(AppConstants.booksBox);
  final Uuid _uuid = const Uuid();
  BookModel? findStoreBook(UnifiedBook book) {
    for (final existing in _booksBox.values) {
      if (existing.storeBookId != null) {
        if (existing.storeBookId == book.id) return existing;
        continue;
      }
      if (existing.md5?.isNotEmpty == true && book.md5?.isNotEmpty == true) {
        if (existing.md5!.toLowerCase() == book.md5!.toLowerCase()) {
          return existing;
        }
        continue;
      }
      // Compatibility for pre-existing entries that lack a source identifier.
      if (existing.md5 == null &&
          book.md5 == null &&
          existing.title == book.title &&
          existing.author == book.author &&
          existing.format == book.extension) {
        return existing;
      }
    }
    return null;
  }

  /// Get all books from library sorted by last read time
  List<BookModel> getAllBooks() {
    final books = _booksBox.values.toList();
    for (final book in books) {
      debugPrint(
        '📚 Loaded book: ${book.title}, Progress: ${book.lastReadProgress}, Page: ${book.lastReadPage}',
      );
    }
    books.sort((a, b) => b.lastReadTime.compareTo(a.lastReadTime));
    return books;
  }

  /// Watch for changes in the books box
  Stream<BoxEvent> get watchBooks => _booksBox.watch();

  /// Get a specific book by ID
  BookModel? getBook(String id) {
    try {
      return _booksBox.values.firstWhere((book) => book.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Import cancellation is distinct from invalid/corrupt book errors.
  Future<BookModel?> importBook() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConstants.supportedFormats,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    if (file.path == null) {
      throw const FormatException('The selected book cannot be accessed.');
    }
    final appDir = await getApplicationDocumentsDirectory();
    return importBookFile(
      File(file.path!),
      Directory('${appDir.path}/books'),
      originalName: file.name,
    );
  }

  Future<BookModel> importBookFile(
    File source,
    Directory directory, {
    String? originalName,
  }) async {
    final name = originalName ?? source.uri.pathSegments.last;
    final format = name.split('.').last.toLowerCase();
    await BookFileValidator.validate(source, format);
    await directory.create(recursive: true);
    // Unique managed paths prevent a second import from overwriting the first.
    final target = File('${directory.path}/${_uuid.v4()}.$format');
    await source.copy(target.path);
    try {
      var title = _extractTitleFromFileName(name);
      var author = 'Unknown Author';
      if (format == 'epub') {
        final input = InputFileStream(target.path);
        try {
          final archive = ZipDecoder().decodeStream(input);
          final container = archive.findFile('META-INF/container.xml')!;
          final xml = XmlDocument.parse(utf8.decode(container.content));
          final packagePath = xml
              .findAllElements('rootfile')
              .first
              .getAttribute('full-path')!;
          final package = archive.findFile(packagePath);
          if (package != null && package.size <= 2 * 1024 * 1024) {
            final opf = XmlDocument.parse(utf8.decode(package.content));
            final titles = opf.descendants.whereType<XmlElement>().where(
              (e) => e.name.local == 'title',
            );
            final authors = opf.descendants.whereType<XmlElement>().where(
              (e) => e.name.local == 'creator',
            );
            if (titles.isNotEmpty && titles.first.innerText.trim().isNotEmpty) {
              title = titles.first.innerText.trim();
            }
            if (authors.isNotEmpty) {
              author = authors.map((e) => e.innerText.trim()).join(', ');
            }
          }
        } finally {
          await input.close();
        }
      }
      File? cover;
      try {
        cover = format == 'pdf'
            ? await _extractCoverFromPdf(target)
            : await _extractCoverFromEpub(target);
      } catch (_) {
        /* A missing cover must not prevent importing a valid book. */
      }
      final book = BookModel(
        id: _uuid.v4(),
        title: title,
        author: author,
        localPath: target.path,
        format: format,
        fileSize: await target.length(),
        localCoverPath: cover?.path,
      );
      await _booksBox.put(book.id, book);
      return book;
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  Future<File?> _extractCoverFromPdf(File file) async {
    final document = await PdfDocument.openFile(file.path);
    try {
      if (document.pages.isEmpty) return null;
      final page = document.pages.first;
      final rendered = await page.render(
        width: 300,
        height: (300 * page.height / page.width).round(),
      );
      if (rendered == null) return null;
      try {
        final image = await rendered.createImage();
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null) return null;
          return await _saveCoverImage(png.buffer.asUint8List(), 'png');
        } finally {
          image.dispose();
        }
      } finally {
        rendered.dispose();
      }
    } finally {
      await document.dispose();
    }
  }

  Future<File?> _extractCoverFromEpub(File file) async {
    final input = InputFileStream(file.path);
    try {
      final archive = ZipDecoder().decodeStream(input);

      // Find container.xml
      final containerFile = archive.findFile('META-INF/container.xml');
      if (containerFile == null) return null;

      final containerXml = XmlDocument.parse(
        utf8.decode(containerFile.content),
      );
      final rootfile = containerXml.findAllElements('rootfile').first;
      final fullPath = rootfile.getAttribute('full-path');
      if (fullPath == null) return null;

      // Find OPF file
      final opfFile = archive.findFile(fullPath);
      if (opfFile == null) return null;

      final opfXml = XmlDocument.parse(utf8.decode(opfFile.content));
      final manifest = opfXml.findAllElements('manifest').first;

      // Strategy 1: Look for meta name="cover"
      String? coverId;
      try {
        final metadata = opfXml.findAllElements('metadata').first;
        final metaCover = metadata
            .findAllElements('meta')
            .firstWhere((element) => element.getAttribute('name') == 'cover');
        coverId = metaCover.getAttribute('content');
      } catch (_) {}

      // Strategy 2: Look for item with properties="cover-image"
      if (coverId == null) {
        try {
          final coverItem = manifest
              .findAllElements('item')
              .firstWhere(
                (element) => (element.getAttribute('properties') ?? '')
                    .split(' ')
                    .contains('cover-image'),
              );
          coverId = coverItem.getAttribute('id');
        } catch (_) {}
      }

      // If we found an ID, find the href
      String? coverHref;
      if (coverId != null) {
        try {
          final item = manifest
              .findAllElements('item')
              .firstWhere((element) => element.getAttribute('id') == coverId);
          coverHref = item.getAttribute('href');
        } catch (_) {}
      }

      // Strategy 3: Heuristic search for "cover" in href
      if (coverHref == null) {
        try {
          final item = manifest
              .findAllElements('item')
              .firstWhere(
                (element) =>
                    (element.getAttribute('href') ?? '').toLowerCase().contains(
                      'cover',
                    ) &&
                    (element.getAttribute('media-type') ?? '').startsWith(
                      'image/',
                    ),
              );
          coverHref = item.getAttribute('href');
        } catch (_) {}
      }

      if (coverHref == null) return null;

      // Resolve path (it might be relative to OPF)

      // Try with direct concatenation
      String zipPath = Uri.decodeComponent(
        Uri.parse(fullPath).resolve(coverHref).path,
      );
      // Also try raw href just in case
      final simplePath = coverHref;

      ArchiveFile? coverImageFile = archive.findFile(zipPath);
      coverImageFile ??= archive.findFile(simplePath);

      if (coverImageFile == null || coverImageFile.size > 10 * 1024 * 1024) {
        return null;
      }

      return await _saveCoverImage(
        coverImageFile.content,
        coverHref.split('.').last,
      );
    } catch (e) {
      debugPrint('Error extracting EPUB cover: $e');
      return null;
    } finally {
      await input.close();
    }
  }

  Future<File> _saveCoverImage(List<int> bytes, String extension) async {
    final appDir = await getApplicationDocumentsDirectory();
    final coversDir = Directory('${appDir.path}/covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    final coverPath = '${coversDir.path}/${_uuid.v4()}.$extension';
    final file = File(coverPath);
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Add a book downloaded from store
  Future<BookModel> addStoreBook({
    required String title,
    required String author,
    required String localPath,
    required String format,
    String? coverUrl,
    String? md5,
    int? fileSize,
    String? storeBookId,
  }) async {
    await BookFileValidator.validate(File(localPath), format);
    final book = BookModel(
      id: _uuid.v4(),
      title: title,
      author: author,
      localPath: localPath,
      format: format,
      coverUrl: coverUrl,
      md5: md5,
      fileSize: fileSize,
      storeBookId: storeBookId,
    );

    await _booksBox.put(book.id, book);
    return book;
  }

  /// Update reading progress for a book
  Future<void> updateReadingProgress({
    required String bookId,
    required int page,
    required double progress,
    String? cfi,
    int? totalPages,
  }) async {
    final book = getBook(bookId);
    if (book == null) {
      debugPrint('⚠️ updateReadingProgress: Book $bookId not found');
      return;
    }

    book.lastReadPage = page < 0 ? 0 : page;
    book.lastReadProgress = progress.isFinite ? progress.clamp(0.0, 1.0) : 0;
    if (totalPages != null && totalPages > 0) book.totalPages = totalPages;
    book.lastReadCfi = cfi;
    book.lastReadTime = DateTime.now();

    // Use put() instead of save() so Hive.watch() fires and the library refreshes
    await _booksBox.put(book.id, book);
    debugPrint(
      '📖 Progress updated: ${book.title} -> ${(progress * 100).toStringAsFixed(1)}% (CFI: ${cfi != null && cfi.length > 30 ? cfi.substring(0, 30) : cfi ?? 'none'})',
    );
  }

  /// Delete a book from library
  Future<void> deleteBook(String id) async {
    final book = getBook(id);
    if (book == null) return;

    // Delete the file
    try {
      final file = File(book.localPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Silently fail - file might already be deleted
    }

    if (book.localCoverPath != null) {
      final cover = File(book.localCoverPath!);
      if (await cover.exists()) await cover.delete();
    }

    // Remove from Hive
    await _booksBox.delete(id);
  }

  /// Extract title from file name
  String _extractTitleFromFileName(String fileName) {
    // Remove extension
    final withoutExt = fileName.replaceAll(
      RegExp(r'\.(pdf|epub)$', caseSensitive: false),
      '',
    );
    // Replace underscores and dashes with spaces
    final cleaned = withoutExt.replaceAll(RegExp(r'[_-]'), ' ');
    // Capitalize first letter of each word
    return cleaned
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  /// Get books directory path
  Future<String> getBooksDirectoryPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/books';
  }
}
