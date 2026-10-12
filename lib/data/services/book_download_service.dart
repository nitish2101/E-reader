import 'cancellation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:uuid/uuid.dart';
import '../models/store_book.dart';
import 'book_file_validator.dart';
import 'book_search_providers.dart';

class BookDownloadService {
  final Dio dio;
  final Future<Directory> Function() booksDirectory;
  final Future<Map<String, String>> Function(Uri)? requestHeaders;
  BookDownloadService(this.dio, this.booksDirectory, {this.requestHeaders});

  Future<String> download(
    UnifiedBook book,
    CancelToken token,
    void Function(double) onProgress,
  ) async {
    if (!book.isSupported) {
      throw const StoreRepositoryException(
        'Only PDF and EPUB books can be downloaded.',
      );
    }
    final directory = await booksDirectory();
    await directory.create(recursive: true);
    final safeTitle = book.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final title = safeTitle.isEmpty
        ? 'book'
        : safeTitle.substring(0, safeTitle.length > 80 ? 80 : safeTitle.length);
    final destination = File(
      '${directory.path}/${const Uuid().v4()}_$title.${book.extension}',
    );
    final partial = File('${destination.path}.part');
    final queue = <({String url, int depth, int attempt})>[
      if (book.downloadUrl != null)
        (url: book.downloadUrl!, depth: 0, attempt: 0),
      ...book.alternateUrls.map((url) => (url: url, depth: 0, attempt: 0)),
      if (book.detailUrl != null) (url: book.detailUrl!, depth: 0, attempt: 0),
      if (book.md5 != null) ...[
        (url: 'https://library.lol/main/${book.md5}', depth: 0, attempt: 0),
        (
          url: 'https://libgen.li/ads.php?md5=${book.md5}',
          depth: 0,
          attempt: 0,
        ),
      ],
    ];
    final visited = <String>{};
    String reason = 'No usable download link was provided.';
    final timer = Timer(
      const Duration(minutes: 3),
      () => token.cancel(
        TimeoutException('Download timed out. Try another source.'),
      ),
    );
    try {
      while (queue.isNotEmpty && visited.length <= 12) {
        token.throwIfCancellationRequested();
        final candidate = queue.removeAt(0);
        if (!BookSearchProviders.isHttpUrl(candidate.url) ||
            (candidate.attempt == 0 &&
                (visited.length >= 12 || !visited.add(candidate.url)))) {
          continue;
        }
        try {
          onProgress(0);
          final sessionHeaders =
              await requestHeaders?.call(Uri.parse(candidate.url)) ??
              <String, String>{};
          token.throwIfCancellationRequested();
          final response = await dio.get<ResponseBody>(
            candidate.url,
            cancelToken: token,
            options: Options(
              responseType: ResponseType.stream,
              // Refresh cookies for each destination, never forward an archive
              // session to a different download host through an auto redirect.
              followRedirects: false,
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 400,
              receiveTimeout: const Duration(seconds: 25),
              headers: {
                ...sessionHeaders,
                'Accept':
                    'application/epub+zip,application/pdf,text/html;q=0.5,*/*;q=0.1',
              },
            ),
          );
          final body = response.data;
          if (body == null) continue;
          if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
            await body.stream.drain<void>();
            final location = response.headers.value('location');
            if (location != null) {
              queue.insert(0, (
                url: response.realUri.resolve(location).toString(),
                depth: candidate.depth,
                attempt: 0,
              ));
            }
            reason = 'The download server returned an unusable redirect.';
            continue;
          }
          final encoding = response.headers
              .value(Headers.contentEncodingHeader)
              ?.toLowerCase();
          final total = encoding == null || encoding == 'identity'
              ? int.tryParse(
                      response.headers.value(Headers.contentLengthHeader) ?? '',
                    ) ??
                    -1
              : -1;
          final mime =
              response.headers
                  .value(Headers.contentTypeHeader)
                  ?.toLowerCase() ??
              '';
          if (mime.contains('text/html') ||
              mime.contains('application/xhtml')) {
            final bytes = <int>[];
            await for (final chunk in body.stream) {
              token.throwIfCancellationRequested();
              bytes.addAll(chunk);
              if (bytes.length > 2 * 1024 * 1024) {
                throw const FormatException('Download page is too large.');
              }
            }
            if (candidate.depth < 2) {
              final links = extractDownloadLinks(
                utf8.decode(bytes, allowMalformed: true),
                response.realUri,
              );
              queue.insertAll(
                0,
                links.map(
                  (url) => (url: url, depth: candidate.depth + 1, attempt: 0),
                ),
              );
            }
            reason =
                'The source returned a web page, login, or waiting screen instead of a book.';
            continue;
          }
          if (total > BookFileValidator.maxFileBytes) {
            throw const FormatException('The book exceeds the 300 MB limit.');
          }
          final sink = partial.openWrite(mode: FileMode.write);
          var received = 0;
          try {
            await for (final chunk in body.stream) {
              token.throwIfCancellationRequested();
              received += chunk.length;
              if (received > BookFileValidator.maxFileBytes) {
                throw const FormatException(
                  'The book exceeds the 300 MB limit.',
                );
              }
              sink.add(chunk);
              if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
            }
            await sink.flush();
          } finally {
            await sink.close();
          }
          if (total >= 0 && received != total) {
            throw const FormatException('The download was interrupted.');
          }
          await BookFileValidator.validate(partial, book.extension);
          token.throwIfCancellationRequested();
          await partial.rename(destination.path);
          onProgress(1);
          return destination.path;
        } on DioException catch (error) {
          if (CancelToken.isCancel(error)) rethrow;
          final status = error.response?.statusCode;
          final transient =
              (status != null &&
                  (status >= 500 || status == 408 || status == 429)) ||
              error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.connectionError;
          if (candidate.attempt == 0 && transient) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            token.throwIfCancellationRequested();
            queue.insert(0, (
              url: candidate.url,
              depth: candidate.depth,
              attempt: 1,
            ));
          }
          reason =
              'The download server is unavailable (${error.response?.statusCode ?? error.type.name}).';
        } on FormatException catch (error) {
          reason = error.message;
        } finally {
          if (await partial.exists()) await partial.delete();
        }
      }
      throw StoreRepositoryException('$reason Try another edition or source.');
    } finally {
      timer.cancel();
      if (await partial.exists()) await partial.delete();
    }
  }

  static List<String> extractDownloadLinks(String body, Uri base) {
    final document = html.parse(body);
    final links = <String>{};
    // Some public catalogs use an immediate HTML refresh to start the transfer.
    // Follow only same-origin book files, within the existing depth/URL limits.
    for (final meta in document.querySelectorAll('meta[http-equiv]')) {
      if (meta.attributes['http-equiv']?.toLowerCase() != 'refresh') continue;
      final match = RegExp(
        r'^\s*0\s*;\s*url\s*=\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(meta.attributes['content'] ?? '');
      if (match == null) continue;
      var target = match.group(1)!.trim();
      if ((target.startsWith('"') && target.endsWith('"')) ||
          (target.startsWith("'") && target.endsWith("'"))) {
        target = target.substring(1, target.length - 1);
      }
      final parsed = Uri.tryParse(target);
      if (parsed == null) continue;
      final uri = base.resolveUri(parsed);
      final path = uri.path.toLowerCase();
      if (BookSearchProviders.isHttpUrl(uri.toString()) &&
          uri.origin == base.origin &&
          (path.endsWith('.epub') || path.endsWith('.pdf'))) {
        links.add(uri.toString());
      }
    }
    for (final link in document.querySelectorAll('a[href]')) {
      final href = link.attributes['href']!;
      final text = link.text.trim().toLowerCase();
      final uri = base.resolve(href);
      final path = uri.path.toLowerCase();
      // Pick actual download controls, never every navigation link on a page.
      if (text == 'get' ||
          text == 'download' ||
          text.startsWith('download now') ||
          path.endsWith('.pdf') ||
          path.endsWith('.epub') ||
          (uri.host == 'www.gutenberg.org' &&
              RegExp(
                r'^/ebooks/\d+\.epub3?\.(images|noimages)$',
              ).hasMatch(path)) ||
          path.contains('/get.php') ||
          path.contains('/ads.php') ||
          uri.host == 'library.lol' ||
          link.attributes.containsKey('download')) {
        if (BookSearchProviders.isHttpUrl(uri.toString())) {
          links.add(uri.toString());
        }
      }
    }
    return links.toList();
  }
}
