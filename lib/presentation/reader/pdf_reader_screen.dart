import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/repositories/book_repository.dart';
import 'bloc/reader_bloc.dart';

class PdfReaderScreen extends StatefulWidget {
  final String bookId;

  const PdfReaderScreen({super.key, required this.bookId});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  PdfViewerController? _controller;
  Timer? _autoSaveTimer;
  bool _showControls = true;
  bool _isInitializing = true;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    // Hide system UI for immersive reading
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    // Auto-save every 5 seconds
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      context.read<ReaderBloc>().add(SaveProgress());
    });
  }

  @override
  void dispose() {
    // Save progress before closing
    context.read<ReaderBloc>().add(SaveProgress());
    
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ReaderBloc(
        bookRepository: context.read<BookRepository>(),
      )..add(LoadBook(widget.bookId)),
      child: BlocBuilder<ReaderBloc, ReaderState>(
        builder: (context, state) {
          if (state is ReaderLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (state is ReaderError) {
            return Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(state.message),
                  ],
                ),
              ),
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
    );
  }

  Widget _buildPdfViewer(BuildContext context, String filePath, int initialPage) {
    final viewer = PdfViewer.file(
      filePath,
      controller: _controller,
      params: PdfViewerParams(
        panEnabled: true,
        // Enable smooth vertical continuous scrolling
        layoutPages: (pages, params) {
          final height = pages.fold(
            0.0,
            (prev, page) => prev + page.height + params.margin,
          );
          final pageLayouts = <Rect>[];
          double y = params.margin;
          // Find max width for document size
          final maxWidth = pages.fold(0.0, (prev, page) => prev > page.width ? prev : page.width);
          for (final page in pages) {
            final x = (maxWidth - page.width) / 2 + params.margin;
            pageLayouts.add(
              Rect.fromLTWH(x, y, page.width, page.height),
            );
            y += page.height + params.margin;
          }
          return PdfPageLayout(
            pageLayouts: pageLayouts,
            documentSize: Size(maxWidth + params.margin * 2, height),
          );
        },
        margin: 8,
        backgroundColor: _isDarkMode ? Colors.white : Theme.of(context).scaffoldBackgroundColor,
        onViewerReady: (document, controller) async {
          _controller = controller;
          _totalPages = document.pages.length;
          
          // Jump to last read page
          if (initialPage > 0 && initialPage <= _totalPages) {
            await controller.goToPage(pageNumber: initialPage);
          }

          _isInitializing = false;
          
          if (mounted) setState(() {});
        },
        onPageChanged: (pageNumber) {
          if (_isInitializing || !mounted) return;

          setState(() {
            _currentPage = pageNumber ?? 1;
          });
          
          context.read<ReaderBloc>().add(UpdatePdfProgress(
            currentPage: _currentPage,
            totalPages: _totalPages,
          ));
        },
      ),
    );

    if (_isDarkMode) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1,  0,  0, 0, 255,
           0, -1,  0, 0, 255,
           0,  0, -1, 0, 255,
           0,  0,  0, 1,   0,
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
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black54,
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
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
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black54,
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Page slider
                      if (_totalPages > 0)
                        Slider(
                          value: _currentPage.toDouble(),
                          min: 1,
                          max: _totalPages.toDouble(),
                          onChanged: (value) {
                            _controller?.goToPage(pageNumber: value.toInt());
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
