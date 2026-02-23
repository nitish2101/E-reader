import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:pdfrx/pdfrx.dart';
import 'dart:ui' as ui;

import '../models/book_model.dart';
import '../../core/constants/app_constants.dart';

class BookRepository {
  final Box<BookModel> _booksBox = Hive.box<BookModel>(AppConstants.booksBox);
  final Uuid _uuid = const Uuid();
  final Dio _dio = Dio();

  /// Get all books from library sorted by last read time
  List<BookModel> getAllBooks() {
    final books = _booksBox.values.toList();
    for (final book in books) {
      debugPrint('📚 Loaded book: ${book.title}, Progress: ${book.lastReadProgress}, Page: ${book.lastReadPage}');
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
      
      // Try to extract cover
      String? localCoverPath;
      String? coverUrl;
      
      try {
        if (format == 'pdf') {
          final coverFile = await _extractCoverFromPdf(File(newPath));
          localCoverPath = coverFile?.path;
        } else if (format == 'epub') {
          final coverFile = await _extractCoverFromEpub(File(newPath));
          localCoverPath = coverFile?.path;
        }
      } catch (e) {
        debugPrint('⚠️ Failed to extract cover: $e');
      }
      
      // Fallback to Open Library if no local cover
      if (localCoverPath == null) {
        try {
          // Clean title for search
          final searchTitle = title.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
          coverUrl = await _fetchCoverFromOpenLibrary(searchTitle, '');
        } catch (e) {
          debugPrint('⚠️ Failed to fetch cover from Open Library: $e');
        }
      }

      // Create book model
      final book = BookModel(
        id: _uuid.v4(),
        title: title,
        author: 'Unknown Author',
        localPath: newPath,
        format: format,
        fileSize: file.size,
        localCoverPath: localCoverPath,
        coverUrl: coverUrl,
      );

      // Save to Hive
      await _booksBox.put(book.id, book);

      return book;
    } catch (e) {
      debugPrint('❌ Error importing book: $e');
      return null;
    }
  }

  Future<File?> _extractCoverFromPdf(File file) async {
    try {
      final document = await PdfDocument.openFile(file.path);
      if (document.pages.isEmpty) return null;
      
      final page = document.pages[0];
      final image = await page.render(
        width: page.width.toInt(),
        height: page.height.toInt(),
        format: PdfImageFormat.png,
      );
      
      if (image == null) return null;
      
      final appDir = await getApplicationDocumentsDirectory();
      final coversDir = Directory('${appDir.path}/covers');
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }
      
      final coverPath = '${coversDir.path}/${_uuid.v4()}.png';
      final coverFile = File(coverPath);
      await coverFile.writeAsBytes(image.pixels);
      
      return coverFile;
    } catch (e) {
      debugPrint('Error extracting PDF cover: $e');
      return null;
    }
  }
  
  Future<File?> _extractCoverFromEpub(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      // Find container.xml
      final containerFile = archive.findFile('META-INF/container.xml');
      if (containerFile == null) return null;
      
      final containerXml = XmlDocument.parse(String.fromCharCodes(containerFile.content));
      final rootfile = containerXml.findAllElements('rootfile').first;
      final fullPath = rootfile.getAttribute('full-path');
      if (fullPath == null) return null;
      
      // Find OPF file
      final opfFile = archive.findFile(fullPath);
      if (opfFile == null) return null;
      
      final opfXml = XmlDocument.parse(String.fromCharCodes(opfFile.content));
      final manifest = opfXml.findAllElements('manifest').first;
      
      // Strategy 1: Look for meta name="cover"
      String? coverId;
      try {
        final metadata = opfXml.findAllElements('metadata').first;
        final metaCover = metadata.findAllElements('meta').firstWhere(
          (element) => element.getAttribute('name') == 'cover',
        );
        coverId = metaCover.getAttribute('content');
      } catch (_) {}
      
      // Strategy 2: Look for item with properties="cover-image"
      if (coverId == null) {
        try {
          final coverItem = manifest.findAllElements('item').firstWhere(
            (element) => element.getAttribute('properties') == 'cover-image',
          );
          coverId = coverItem.getAttribute('id');
        } catch (_) {}
      }
      
      // If we found an ID, find the href
      String? coverHref;
      if (coverId != null) {
        try {
          final item = manifest.findAllElements('item').firstWhere(
            (element) => element.getAttribute('id') == coverId,
          );
          coverHref = item.getAttribute('href');
        } catch (_) {}
      }
      
      // Strategy 3: Heuristic search for "cover" in href
      if (coverHref == null) {
         try {
           final item = manifest.findAllElements('item').firstWhere(
             (element) => (element.getAttribute('href') ?? '').toLowerCase().contains('cover') && 
                          (element.getAttribute('media-type') ?? '').startsWith('image/'),
           );
           coverHref = item.getAttribute('href');
         } catch (_) {}
      }
      
      if (coverHref == null) return null;
      
      // Resolve path (it might be relative to OPF)
      final opfDir = fullPath.contains('/') ? fullPath.substring(0, fullPath.lastIndexOf('/') + 1) : '';
      
      // Try with direct concatenation
      String zipPath = opfDir + coverHref;
      // Also try raw href just in case
      final simplePath = coverHref;
      
      ArchiveFile? coverImageFile = archive.findFile(zipPath);
      if (coverImageFile == null) {
        coverImageFile = archive.findFile(simplePath);
      }
      
      if (coverImageFile == null) return null;
      
      return await _saveCoverImage(coverImageFile.content, coverHref.split('.').last);
      
    } catch (e) {
      debugPrint('Error extracting EPUB cover: $e');
      return null;
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
  
  Future<String?> _fetchCoverFromOpenLibrary(String title, String author) async {
    try {
      final query = 'title=$title${author.isNotEmpty && author != "Unknown Author" ? '&author=$author' : ''}';
      final response = await _dio.get(
        'https://openlibrary.org/search.json?$query&limit=1',
        options: Options(responseType: ResponseType.json),
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['docs'] != null && (data['docs'] as List).isNotEmpty) {
          final doc = data['docs'][0];
          if (doc['cover_i'] != null) {
            final coverId = doc['cover_i'];
            return 'https://covers.openlibrary.org/b/id/$coverId-L.jpg';
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching from Open Library: $e');
    }
    return null;
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
    if (book == null) {
      debugPrint('⚠️ updateReadingProgress: Book $bookId not found');
      return;
    }

    book.lastReadPage = page;
    book.lastReadProgress = progress;
    book.lastReadCfi = cfi;
    book.lastReadTime = DateTime.now();

    // Use put() instead of save() so Hive.watch() fires and the library refreshes
    await _booksBox.put(book.id, book);
    debugPrint('📖 Progress updated: ${book.title} -> ${(progress * 100).toStringAsFixed(1)}% (CFI: ${cfi != null && cfi.length > 30 ? cfi.substring(0, 30) : cfi ?? 'none'})');
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
