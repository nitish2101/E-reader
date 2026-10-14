import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/repositories/book_repository.dart';
import 'bloc/reader_bloc.dart';
import '../statistics/reader_activity_scope.dart';

class PdfReaderScreen extends StatefulWidget {
  final String bookId;

  const PdfReaderScreen({super.key, required this.bookId});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen>
    with WidgetsBindingObserver {
  final _readingActivity = ReaderActivityController();
  late final ReaderBloc _readerBloc;
  PdfViewerController? _controller;
  Timer? _autoSaveTimer;
  Timer? _openingTimer;
  bool _openingStalled = false;
  int _viewerGeneration = 0;
  bool _allowPop = false;
  bool _closing = false;
  bool _showControls = true;
  bool _isInitializing = true;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startOpeningTimer();
    _readerBloc = ReaderBloc(bookRepository: context.read<BookRepository>())
      ..add(LoadBook(widget.bookId));
    // Hide system UI for immersive reading
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Auto-save every 5 seconds
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_checkpoint());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _openingTimer?.cancel();
    // Save progress before closing
    unawaited(_readerBloc.close());

    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _autoSaveTimer?.cancel();
    _readingActivity.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_checkpoint());
    }
  }

  Future<void> _checkpoint() async {
    if (_isInitializing || _totalPages == 0) return;
    try {
      final page = _controller?.isReady == true
          ? _controller!.pageNumber ?? _currentPage
          : _currentPage;
      await _readerBloc.checkpointPdf(page, _totalPages);
    } catch (error) {
      debugPrint('Failed to checkpoint PDF: $error');
    }
  }

  Future<void> _closeReader() async {
    if (_closing) return;
    _closing = true;
    _readingActivity.setLoaded(false);
    _autoSaveTimer?.cancel();
    await _checkpoint();
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  void _startOpeningTimer() {
    _openingTimer?.cancel();
    _openingTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _isInitializing) setState(() => _openingStalled = true);
    });
  }

  Future<void> _retryViewer() async {
    _readingActivity.setLoaded(false);
    _readingActivity.setBlocked(false);
    _readingActivity.cancelNavigation();
    await _checkpoint();
    if (!mounted) return;
    setState(() {
      _viewerGeneration++;
      _controller = null;
      _isInitializing = true;
      _openingStalled = false;
    });
    _readerBloc.add(LoadBook(widget.bookId));
    _startOpeningTimer();
  }

  Widget _recoveryControls(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          FilledButton(onPressed: _retryViewer, child: const Text('Retry')),
          TextButton(
            onPressed: _closeReader,
            child: const Text('Return to library'),
          ),
        ],
      ),
    ),
  );

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ReaderActivityScope(
      bookId: widget.bookId,
      controller: _readingActivity,
      child: _buildReader(context),
    );
  }

  Widget _buildReader(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_closeReader());
      },
      child: BlocProvider.value(
        value: _readerBloc,
        child: BlocBuilder<ReaderBloc, ReaderState>(
          builder: (context, state) {
            if (state is ReaderLoading) {
              return Scaffold(
                body: _openingStalled
                    ? _recoveryControls(
                        'This book is taking longer to open. Loading continues.',
                      )
                    : const Center(child: CircularProgressIndicator()),
              );
            }

            if (state is ReaderError) {
              return Scaffold(
                appBar: AppBar(),
                body: _recoveryControls(state.message),
              );
            }

            if (state is ReaderLoaded || state is ProgressSaved) {
              final book = state is ReaderLoaded
                  ? state.book
                  : (state as ProgressSaved).book;
              final initialPage = state is ReaderLoaded
                  ? state.currentPage
                  : (state as ProgressSaved).currentPage;

              return Scaffold(
                body: Stack(
                  children: [
                    // PDF viewer - handles all scroll gestures naturally
                    _buildPdfViewer(context, book.localPath, initialPage),
                    if (_openingStalled && _isInitializing)
                      _recoveryControls(
                        'This book is taking longer to open. Loading continues.',
                      ),
                    // Top bar
                    _buildTopBar(context, book.title),
                    // Bottom bar
                    _buildBottomBar(context),
                    // Tap detector only at top center (when controls are hidden)
                    if (!_showControls)
                      Positioned(
                        top: 0,
                        left: MediaQuery.of(context).size.width * 0.4,
                        right: MediaQuery.of(context).size.width * 0.4,
                        height: 60,
                        child: GestureDetector(
                          onTap: _toggleControls,
                          behavior: HitTestBehavior.opaque,
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                  ],
                ),
              );
            }

            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPdfViewer(
    BuildContext context,
    String filePath,
    int initialPage,
  ) {
    final generation = _viewerGeneration;
    final viewer = PdfViewer.file(
      filePath,
      key: ValueKey(generation),
      controller: _controller,
      params: PdfViewerParams(
        panEnabled: true,
        errorBannerBuilder: (context, error, stack, document) =>
            _recoveryControls('Could not open this PDF. $error'),
        // Enable smooth vertical continuous scrolling
        layoutPages: (pages, params) {
          final height = pages.fold(
            0.0,
            (prev, page) => prev + page.height + params.margin,
          );
          final pageLayouts = <Rect>[];
          double y = params.margin;
          // Find max width for document size
          final maxWidth = pages.fold(
            0.0,
            (prev, page) => prev > page.width ? prev : page.width,
          );
          for (final page in pages) {
            final x = (maxWidth - page.width) / 2 + params.margin;
            pageLayouts.add(Rect.fromLTWH(x, y, page.width, page.height));
            y += page.height + params.margin;
          }
          return PdfPageLayout(
            pageLayouts: pageLayouts,
            documentSize: Size(maxWidth + params.margin * 2, height),
          );
        },
        margin: 8,
        backgroundColor: _isDarkMode
            ? Colors.white
            : Theme.of(context).scaffoldBackgroundColor,
        onViewerReady: (document, controller) async {
          if (!mounted || generation != _viewerGeneration) return;
          _controller = controller;
          _totalPages = document.pages.length;

          // Jump to last read page
          if (initialPage > 0 && initialPage <= _totalPages) {
            await controller.goToPage(pageNumber: initialPage);
          }

          if (!mounted || generation != _viewerGeneration || _closing) return;
          _openingTimer?.cancel();
          _openingStalled = false;
          _currentPage =
              controller.pageNumber ?? initialPage.clamp(1, _totalPages);
          _isInitializing = false;
          _readingActivity.setLoaded(true);
          _readerBloc.confirmPdfPosition(_currentPage, _totalPages);

          if (mounted) setState(() {});
        },
        onDocumentChanged: (document) {
          if (mounted && generation == _viewerGeneration && document == null) {
            _readingActivity.setLoaded(false);
          }
        },
        onPageChanged: (pageNumber) {
          if (_isInitializing || !mounted || generation != _viewerGeneration) {
            return;
          }

          setState(() {
            _currentPage = pageNumber ?? 1;
          });

          _readerBloc.confirmPdfPosition(_currentPage, _totalPages);
        },
      ),
    );

    if (_isDarkMode) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1,
          0,
          0,
          0,
          255,
          0,
          -1,
          0,
          0,
          255,
          0,
          0,
          -1,
          0,
          255,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: viewer,
      );
    }

    return viewer;
  }

  Widget _buildTopBar(BuildContext context, String title) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_showControls,
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: GestureDetector(
            onTap: _toggleControls,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: _closeReader,
                      ),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white),
                        onPressed: () {
                          _showSettings(context);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final generation = _viewerGeneration;
    final progress = _totalPages > 0 ? _currentPage / _totalPages : 0.0;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_showControls,
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: GestureDetector(
            onTap: _toggleControls,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Page slider
                      if (_totalPages > 1)
                        Slider(
                          value: _currentPage.toDouble(),
                          min: 1,
                          max: _totalPages.toDouble(),
                          onChangeStart: (_) {
                            if (generation == _viewerGeneration &&
                                !_isInitializing) {
                              _readingActivity.setBlocked(true);
                            }
                          },
                          onChanged: (value) {
                            if (generation == _viewerGeneration &&
                                !_isInitializing) {
                              unawaited(_seekPage(value.toInt()));
                            }
                          },
                          onChangeEnd: (_) {
                            if (generation == _viewerGeneration) {
                              _readingActivity.setBlocked(false);
                            }
                          },
                        ),
                      // Page indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Page $_currentPage of $_totalPages',
                            style: const TextStyle(color: Colors.white),
                          ),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _seekPage(int page) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await _readingActivity.navigate(
        () => controller.goToPage(pageNumber: page),
      );
    } on TimeoutException {
      // pdfrx cancels superseded animation futures without completing them.
    } catch (error) {
      debugPrint('PDF page navigation failed: $error');
    }
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Settings',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            SwitchListTile(
              title: const Text('Dark Mode'),
              subtitle: const Text('Invert colors for night reading'),
              value: _isDarkMode,
              onChanged: (value) {
                setState(() {
                  _isDarkMode = value;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
