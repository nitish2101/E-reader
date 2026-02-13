import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';

import '../models/book_model.dart';
import '../../core/constants/app_constants.dart';

class BookRepository {
  final Box<BookModel> _booksBox = Hive.box<BookModel>(AppConstants.booksBox);
  final Uuid _uuid = const Uuid();

  /// Get all books from library sorted by last read time
  List<BookModel> getAllBooks() {
    final books = _booksBox.values.toList();
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

  /// Import a book from file picker
  Future<BookModel?> importBook() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: AppConstants.supportedFormats,
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final file = result.files.first;
      if (file.path == null) return null;

      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final booksDir = Directory('${appDir.path}/books');
      if (!await booksDir.exists()) {
        await booksDir.create(recursive: true);
      }

      // Copy file to app directory
      final fileName = file.name;
      final newPath = '${booksDir.path}/$fileName';
      final sourceFile = File(file.path!);
      await sourceFile.copy(newPath);

      // Extract book info
      final format = file.extension?.toLowerCase() ?? 'pdf';
      final title = _extractTitleFromFileName(fileName);

      // Create book model
      final book = BookModel(
        id: _uuid.v4(),
        title: title,
        author: 'Unknown Author',
        localPath: newPath,
        format: format,
        fileSize: file.size,
      );

      // Save to Hive
      await _booksBox.put(book.id, book);

      return book;
    } catch (e) {
      print('Error importing book: $e');
      return null;
    }
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
  }) async {
    final book = BookModel(
      id: _uuid.v4(),
      title: title,
      author: author,
      localPath: localPath,
      format: format,
      coverUrl: coverUrl,
      md5: md5,
      fileSize: fileSize,
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
    if (book == null) return;

    book.lastReadPage = page;
    book.lastReadProgress = progress;
    book.lastReadCfi = cfi;
    book.lastReadTime = DateTime.now();

    // Use put() instead of save() so Hive.watch() fires and the library refreshes
    await _booksBox.put(book.id, book);
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
      print('Error deleting book file: $e');
    }

    // Remove from Hive
    await _booksBox.delete(id);
  }

  /// Extract title from file name
  String _extractTitleFromFileName(String fileName) {
    // Remove extension
    final withoutExt = fileName.replaceAll(RegExp(r'\.(pdf|epub)$', caseSensitive: false), '');
    // Replace underscores and dashes with spaces
    final cleaned = withoutExt.replaceAll(RegExp(r'[_-]'), ' ');
    // Capitalize first letter of each word
    return cleaned.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Get books directory path
  Future<String> getBooksDirectoryPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/books';
  }
}
