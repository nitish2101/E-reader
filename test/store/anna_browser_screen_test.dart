import 'package:ereader/data/repositories/store_repository.dart';
import 'package:ereader/presentation/store/anna_browser_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/anna_webview.dart';

void main() {
  testWidgets(
    'download verification resumes automatically with book identity intact',
    (tester) async {
      installAnnaWebView();
      final repository = StoreRepository();
      addTearDown(repository.dispose);
      const book = UnifiedBook(
        title: 'My book',
        author: 'An author',
        extension: 'epub',
        source: BookSource.annasArchive,
        md5: 'abc',
        detailUrl: 'https://annas-archive.pk/md5/abc',
      );
      AnnaBrowserResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.push<AnnaBrowserResult>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AnnaBrowserScreen(
                      repository: repository,
                      initialUrl: Uri.parse(book.detailUrl!),
                      book: book,
                    ),
                  ),
                );
              },
              child: const Text('Store'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Store'));
      await tester.pumpAndSettle();
      final page = AnnaPageController()..url = WebUri(book.detailUrl!);
      final controller = InAppWebViewController.fromPlatform(platform: page);
      annaViewParams!.onWebViewCreated!(controller);
      annaViewParams!.onLoadStop?.call(controller, page.url);
      await tester.pump(const Duration(seconds: 1));
      expect(result, isNull);
      page.body = '<a href="https://files.example/book.epub">Download now</a>';
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(result?.download?.downloadUrl, 'https://files.example/book.epub');
      expect(result?.download?.id, 'abc');
      expect(result?.download?.title, 'My book');
      expect(find.byType(AnnaBrowserScreen), findsNothing);
    },
  );
  testWidgets(
    'verified search returns to Store automatically, including delayed page updates',
    (tester) async {
      installAnnaWebView();
      final repository = StoreRepository();
      addTearDown(repository.dispose);
      AnnaBrowserResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.push<AnnaBrowserResult>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AnnaBrowserScreen(
                      repository: repository,
                      initialUrl: Uri.parse(
                        'https://annas-archive.pk/search?q=book',
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Store'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Store'));
      await tester.pumpAndSettle();
      final view = annaViewParams!;
      final page = AnnaPageController();
      final controller = InAppWebViewController.fromPlatform(platform: page);
      view.onWebViewCreated!(controller);
      view.onLoadStop?.call(controller, page.url);
      await tester.pump(const Duration(seconds: 1));
      expect(result, isNull);
      expect(find.byType(AnnaBrowserScreen), findsOneWidget);
      page.body =
          '<div class="flex pt-3"><div class="text-gray-800">English EPUB 1 MB</div><a href="/md5/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">A book</a></div><a href="/search?q=book&page=2">Next</a>';
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(result?.search?.books.single.title, 'A book');
      expect(result?.search?.hasMore, isTrue);
      expect(find.byType(AnnaBrowserScreen), findsNothing);
    },
  );
}
