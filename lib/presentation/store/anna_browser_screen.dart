import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../data/repositories/store_repository.dart';
import '../../data/services/book_search_providers.dart';

class AnnaBrowserResult {
  final StoreSearchResult? search;
  final UnifiedBook? download;
  const AnnaBrowserResult({this.search, this.download});
}

/// The user completes the source's own verification in a normal WebView.
/// Read search HTML only on request; never solve or skip the challenge.
class AnnaBrowserScreen extends StatefulWidget {
  final StoreRepository repository;
  final Uri initialUrl;
  final UnifiedBook? book;
  const AnnaBrowserScreen({
    super.key,
    required this.repository,
    required this.initialUrl,
    this.book,
  });

  @override
  State<AnnaBrowserScreen> createState() => _AnnaBrowserScreenState();
}

class _AnnaBrowserScreenState extends State<AnnaBrowserScreen> {
  InAppWebViewController? _controller;
  Uri? _url;
  String? _error;
  int _progress = 0;
  bool _busy = false;

  Future<void> _registerSession(Uri url) async {
    final userAgent = await _controller?.evaluateJavascript(
      source: 'navigator.userAgent',
    );
    if (userAgent is! String || userAgent.isEmpty) return;
    // Capture the cookie manager, not the soon-to-be-disposed WebView. Native
    // cookie lookup applies domain/path rules separately to every requested URL.
    final cookies = CookieManager.instance();
    widget.repository.registerBrowserSession(url, (uri) async {
      final values = await cookies.getCookies(url: WebUri(uri.toString()));
      return {
        'User-Agent': userAgent,
        if (values.isNotEmpty)
          'Cookie': values.map((c) => '${c.name}=${c.value}').join('; '),
      };
    });
  }

  Future<void> _useResults() async {
    if (_busy || _controller == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await _controller!.getUrl();
      if (url == null || !widget.repository.isAnnaUrl(url.uriValue)) {
        throw const StoreRepositoryException(
          'Open an Anna’s Archive search page first.',
        );
      }
      final body = await _controller!.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      if (body is! String) {
        throw const StoreRepositoryException('This page is still loading.');
      }
      final result = BookSearchProviders.parseAnna(body, url.uriValue, 1);
      await _registerSession(url.uriValue);
      if (mounted) Navigator.pop(context, AnnaBrowserResult(search: result));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StoreRepositoryException
              ? '${e.message} Complete the site’s check or try another mirror.'
              : 'Could not read this page. Finish verification and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(DownloadStartRequest request) async {
    if (_busy || !BookSearchProviders.isHttpUrl(request.url.toString())) return;
    setState(() => _busy = true);
    try {
      await _registerSession(request.url.uriValue);
      final book = widget.book;
      final name =
          request.suggestedFilename ??
          request.url.uriValue.pathSegments.lastOrNull ??
          'Book';
      final extension =
          book?.extension ??
          (request.mimeType == 'application/pdf' ||
                  name.toLowerCase().endsWith('.pdf')
              ? 'pdf'
              : request.mimeType == 'application/epub+zip' ||
                    name.toLowerCase().endsWith('.epub')
              ? 'epub'
              : '');
      if (extension.isEmpty) {
        throw const StoreRepositoryException('Choose an EPUB or PDF download.');
      }
      final download = UnifiedBook(
        title: book?.title ?? name,
        author: book?.author ?? 'Unknown Author',
        md5: book?.md5,
        extension: extension,
        source: BookSource.annasArchive,
        coverUrl: book?.coverUrl,
        detailUrl: book?.detailUrl,
        downloadUrl: request.url.toString(),
      );
      if (mounted) {
        Navigator.pop(context, AnnaBrowserResult(download: download));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StoreRepositoryException
              ? e.message
              : 'Could not start this download. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_url?.host ?? widget.initialUrl.host),
      actions: [
        IconButton(
          tooltip: 'Reload page',
          icon: const Icon(Icons.refresh),
          onPressed: () => _controller?.reload(),
        ),
        PopupMenuButton<Uri>(
          tooltip: 'Change mirror',
          onSelected: (mirror) => _controller?.loadUrl(
            urlRequest: URLRequest(
              url: WebUri(
                widget.initialUrl
                    .replace(
                      scheme: mirror.scheme,
                      host: mirror.host,
                      port: mirror.hasPort ? mirror.port : null,
                    )
                    .toString(),
              ),
            ),
          ),
          itemBuilder: (_) => [
            for (final mirror in widget.repository.annaMirrors)
              PopupMenuItem(value: mirror, child: Text(mirror.host)),
          ],
        ),
      ],
    ),
    body: Column(
      children: [
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            widget.book == null
                ? 'Complete any verification, then use the search results or select an EPUB/PDF download.'
                : 'Complete the site’s verification and select a download link to add this book to your library.',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_error!),
          ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(widget.initialUrl.toString()),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              useOnDownloadStart: true,
              useShouldOverrideUrlLoading: true,
            ),
            onWebViewCreated: (controller) => _controller = controller,
            onProgressChanged: (_, progress) {
              if (mounted) setState(() => _progress = progress);
            },
            onUpdateVisitedHistory: (_, url, __) {
              if (mounted && url != null) setState(() => _url = url.uriValue);
            },
            shouldOverrideUrlLoading: (_, action) async =>
                action.request.url != null &&
                    BookSearchProviders.isHttpUrl(action.request.url.toString())
                ? NavigationActionPolicy.ALLOW
                : NavigationActionPolicy.CANCEL,
            onDownloadStartRequest: (_, request) => _download(request),
            onReceivedError: (_, request, error) {
              if (mounted && request.isForMainFrame == true) {
                setState(
                  () => _error =
                      'Could not load this page. Reload or choose another mirror.',
                );
              }
            },
          ),
        ),
        if (widget.book == null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: _busy ? null : _useResults,
                child: const Text('Use search results'),
              ),
            ),
          ),
      ],
    ),
  );
}
