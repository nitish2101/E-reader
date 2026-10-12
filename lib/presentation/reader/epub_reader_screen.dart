import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:hive/hive.dart';
import '../../data/repositories/book_repository.dart';
import 'epub_location_bridge.dart';
import 'widgets/dictionary_dialog.dart';

typedef _ProgressView = ({double progress, bool canSeek, bool animate});

/// EPUB reader screen — completely Bloc-free during reading.
///
/// Architecture:
/// - Book data loaded synchronously from Hive (no Bloc needed)
/// - Progress updates rebuild only the bottom controls, never the reader
/// - Saves to repository on: scroll-stop debounce, back button,
///   app lifecycle pause, and dispose
/// - Resume restores the saved CFI and its line offset with scroll anchoring off
/// - `onRelocated` never triggers setState or Bloc events
class EpubReaderScreen extends StatefulWidget {
  final String bookId;

  const EpubReaderScreen({super.key, required this.bookId});

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen>
    with WidgetsBindingObserver {
  // EPUB controller
  EpubController? _epubController;

  // Book data — loaded once from repository, never changes
  String? _bookTitle;
  String? _bookFilePath;
  String? _initialCfi;
  String? _loadError;
  bool _bookDataLoaded = false;

  // Live progress — local only, zero Bloc interaction
  double _progress = 0.0;
  String? _currentCfi;
  double? _viewportOffset;
  double? _initialViewportOffset;
  bool _allowPop = false;
  bool _isClosing = false;
  String? _currentSelection; // Stores current text selection
  bool _hasDirtyProgress = false;
  double? _previewProgress;
  bool _locationsReady = false;
  bool _isSeeking = false;
  bool _usesDirectLocationEvents = false;
  bool _isPreparingLocationBridge = false;
  int _lastLocationSequence = 0;
  EpubLocation? _pendingSeekLocation;
  final _progressView = ValueNotifier<_ProgressView>((
    progress: 0,
    canSeek: false,
    animate: false,
  ));
  int? _touchPointer;
  Offset? _touchStart;
  DateTime? _touchStartTime;
  bool _touchMoved = false;

  // Save debounce — fires 3s after last scroll
  Timer? _saveDebounceTimer;

  // UI state
  bool _showControls = false;
  bool _isEpubLoading = true; // WebView still loading the EPUB
  bool _isSliderDragging = false;
  List<EpubChapter> _chapters = [];
  Widget? _cachedEpubViewer; // Cached to prevent ANY rebuilds

  // Settings
  int _fontSize = 18;
  String _currentThemeName = 'Light';

  late BookRepository _bookRepository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _epubController = EpubController();
    _loadSavedSettings();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bookRepository = context.read<BookRepository>();
    // Load book data once (synchronous Hive lookup)
    if (!_bookDataLoaded && _loadError == null) {
      _loadBookData();
    }
  }

  /// Load book from Hive — instant, no async needed
  void _loadBookData() {
    final book = _bookRepository.getBook(widget.bookId);
    if (book == null) {
      setState(() => _loadError = 'Book not found');
      return;
    }
    _bookDataLoaded = true;
    _bookTitle = book.title;
    _bookFilePath = book.localPath;
    _progress = book.lastReadProgress.isFinite
        ? book.lastReadProgress.clamp(0.0, 1.0)
        : 0;
    _currentCfi = book.lastReadCfi;
    // Only use CFI if it's a valid epubcfi string
    _initialCfi =
        (book.lastReadCfi != null &&
            book.lastReadCfi!.isNotEmpty &&
            book.lastReadCfi!.startsWith('epubcfi('))
        ? book.lastReadCfi
        : null;
    final viewport = Hive.box('settings').get('epubViewport:${widget.bookId}');
    if (viewport is Map &&
        viewport['cfi'] == _initialCfi &&
        viewport['offset'] is num &&
        (viewport['offset'] as num).isFinite) {
      _initialViewportOffset = (viewport['offset'] as num).toDouble();
    }
    _publishProgress();
    // No setState needed — didChangeDependencies runs before first build
  }

  void _loadSavedSettings() {
    final settingsBox = Hive.box('settings');
    _currentThemeName = settingsBox.get('readerTheme', defaultValue: 'Light');
    _fontSize = settingsBox.get('readerFontSize', defaultValue: 18);
  }

  void _saveSettings() {
    final settingsBox = Hive.box('settings');
    settingsBox.put('readerTheme', _currentThemeName);
    settingsBox.put('readerFontSize', _fontSize);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle & save
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_captureAndSave());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveDebounceTimer?.cancel();
    _saveProgressNow();
    _progressView.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Immediately persist current progress to Hive (no Bloc)
  Future<void> _saveProgressNow() async {
    if (!_hasDirtyProgress) return;
    if (_currentCfi == null || _currentCfi!.isEmpty) return;
    _hasDirtyProgress = false;
    final cfi = _currentCfi;
    final offset = _viewportOffset;
    try {
      await _bookRepository.updateReadingProgress(
        bookId: widget.bookId,
        page: 0,
        progress: _progress,
        cfi: cfi,
      );
      await Hive.box(
        'settings',
      ).put('epubViewport:${widget.bookId}', {'cfi': cfi, 'offset': offset});
    } catch (e) {
      _hasDirtyProgress = true;
      debugPrint('Failed to save progress: $e');
    }
  }

  Future<void> _captureAndSave() async {
    if (!_isEpubLoading && !_isPreparingLocationBridge && !_isSeeking) {
      try {
        final result = await _epubController?.webViewController
            ?.evaluateJavascript(
              source:
                  'window._ereaderSnapshot ? window._ereaderSnapshot() : null',
            )
            .timeout(const Duration(milliseconds: 750));
        if (mounted && result is Map) {
          final data = Map<String, dynamic>.from(result);
          final sequence = data['sequence'];
          if (sequence is int && sequence > _lastLocationSequence) {
            _lastLocationSequence = sequence;
            _recordLocation(
              EpubLocation.fromJson(data),
              offset: data['offset'],
            );
          }
        }
      } catch (e) {
        debugPrint('Failed to sample visible EPUB position: $e');
      }
    }
    await _saveProgressNow();
  }

  Future<void> _closeReader() async {
    if (_isClosing) return;
    _isClosing = true;
    _saveDebounceTimer?.cancel();
    await _captureAndSave();
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  /// Schedule a save after the user stops scrolling for 3 seconds
  void _scheduleSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 3), _saveProgressNow);
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  void _toggleControls() {
    if (!mounted) return;
    setState(() => _showControls = !_showControls);
    unawaited(_setProgressReporting());
  }

  void _publishProgress() {
    _progressView.value = (
      progress: _previewProgress ?? _progress,
      canSeek:
          _locationsReady &&
          !_isEpubLoading &&
          !_isPreparingLocationBridge &&
          !_isSeeking,
      animate: !_isSliderDragging && !_isSeeking,
    );
  }

  void _recordLocation(EpubLocation location, {dynamic offset}) {
    if (!location.progress.isFinite ||
        !location.startCfi.startsWith('epubcfi(')) {
      return;
    }
    final progress = _locationsReady
        ? location.progress.clamp(0.0, 1.0)
        : _progress;
    final viewportOffset = offset is num && offset.isFinite
        ? offset.toDouble()
        : null;
    if (_currentCfi == location.startCfi &&
        _progress == progress &&
        _viewportOffset == viewportOffset) {
      return;
    }
    _currentCfi = location.startCfi;
    _progress = progress;
    _viewportOffset = viewportOffset;
    _hasDirtyProgress = true;
    _publishProgress();
    _scheduleSave();
  }

  Future<void> _refreshLocation() async {
    try {
      await _epubController?.webViewController?.evaluateJavascript(
        source: 'rendition.reportLocation()',
      );
    } catch (e) {
      debugPrint('Failed to refresh EPUB position: $e');
    }
  }

  Future<void> _installLocationBridge() async {
    final webView = _epubController?.webViewController;
    if (webView == null) return;
    try {
      webView.addJavaScriptHandler(
        handlerName: 'ereaderRelocated',
        callback: (args) {
          if (!mounted ||
              !_usesDirectLocationEvents ||
              args.isEmpty ||
              args.first is! Map) {
            return;
          }
          try {
            final data = Map<String, dynamic>.from(args.first as Map);
            final sequence = data['sequence'];
            if (sequence is! int || sequence <= _lastLocationSequence) return;
            final location = EpubLocation.fromJson(data);
            if (!location.progress.isFinite ||
                !location.startCfi.startsWith('epubcfi(')) {
              return;
            }
            _lastLocationSequence = sequence;
            if (_isSeeking) {
              _pendingSeekLocation = location;
              return;
            }
            if (!_isEpubLoading && !_isPreparingLocationBridge && !_isSeeking) {
              _recordLocation(location, offset: data['offset']);
            }
          } catch (e) {
            debugPrint('Invalid EPUB location event: $e');
          }
        },
      );
      final installed = await webView.evaluateJavascript(
        source: epubLocationBridgeScript,
      );
      if (!mounted) return;
      _usesDirectLocationEvents = installed == true;
      if (_usesDirectLocationEvents && _initialCfi != null) {
        await webView.callAsyncJavaScript(
          // The first display may have been shifted by browser anchoring before
          // the bridge was installed. Restore once with anchoring disabled.
          functionBody: '''
            await displayed;
            await rendition.display(cfi);
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            return window._ereaderRestoreOffset(cfi, offset);
          ''',
          arguments: {'cfi': _initialCfi, 'offset': _initialViewportOffset},
        );
      }
      await _setProgressReporting();
    } catch (e) {
      debugPrint('Failed to install EPUB location tracking: $e');
    }
  }

  Future<void> _setProgressReporting() async {
    if (!_usesDirectLocationEvents) return;
    try {
      await _epubController?.webViewController?.evaluateJavascript(
        source:
            'window._ereaderProgressVisible = ${_showControls && !_isSeeking}',
      );
    } catch (e) {
      debugPrint('Failed to update EPUB progress tracking: $e');
    }
  }

  Future<void> _seekToProgress(double value) async {
    _isSliderDragging = false;
    _isSeeking = true;
    _pendingSeekLocation = null;
    _previewProgress = value;
    _saveDebounceTimer?.cancel();
    _publishProgress();
    unawaited(_setProgressReporting());
    try {
      final webView = _epubController?.webViewController;
      if (webView == null) throw StateError('Reader is unavailable');
      // Await the actual chapter display before accepting its reading position.
      // The package's toProgressPercentage method starts navigation but returns
      // before it completes, letting older relocation events move the slider.
      final result = await webView
          .callAsyncJavaScript(
            functionBody: '''
          var target = book.locations.cfiFromPercentage(progress);
          if (!target) throw new Error('Book positions are not ready');
          await rendition.display(target);
          var visible = await rendition.manager.currentLocation();
          var location = rendition.located(visible);
          if (!location || !location.start) throw new Error('Position unavailable');
          return {
            startCfi: location.start.cfi,
            endCfi: location.end.cfi,
            progress: location.start.percentage,
            sequence: window._ereaderLocationSequence =
              (window._ereaderLocationSequence || 0) + 1
          };
        ''',
            arguments: {'progress': value},
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (result?.error != null || result?.value is! Map) {
        throw StateError('Could not confirm reading position');
      }
      var location = EpubLocation.fromJson(
        Map<String, dynamic>.from(result!.value as Map),
      );
      if (!location.progress.isFinite ||
          !location.startCfi.startsWith('epubcfi(')) {
        throw StateError('Invalid reading position');
      }
      final sequence = (result.value as Map)['sequence'];
      if (_usesDirectLocationEvents) {
        if (sequence is! int) {
          throw StateError('Outdated reading position');
        }
        if (sequence <= _lastLocationSequence) {
          // A newer visible position may arrive before the async seek response.
          // Keep that position instead of treating successful navigation as an error.
          if (_pendingSeekLocation == null) {
            throw StateError('Outdated reading position');
          }
          location = _pendingSeekLocation!;
        } else {
          _lastLocationSequence = sequence;
        }
      }
      _recordLocation(location);
    } catch (e) {
      if (!mounted) return;
      debugPrint('Failed to seek in EPUB: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not jump to that position. Try again.'),
        ),
      );
      unawaited(_refreshLocation());
    } finally {
      if (mounted) {
        _isSeeking = false;
        _previewProgress = null;
        _pendingSeekLocation = null;
        _publishProgress();
        unawaited(_setProgressReporting());
        if (_hasDirtyProgress) _scheduleSave();
      }
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_touchPointer != null) {
      _touchMoved = true;
      return;
    }
    _touchPointer = event.pointer;
    _touchStart = event.localPosition;
    _touchStartTime = DateTime.now();
    _touchMoved = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer == _touchPointer &&
        _touchStart != null &&
        (event.localPosition - _touchStart!).distance > 10) {
      _touchMoved = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _touchPointer) return;
    final size = MediaQuery.sizeOf(context);
    final isTap =
        !_touchMoved &&
        _touchStart != null &&
        (event.localPosition - _touchStart!).distance <= 10 &&
        DateTime.now().difference(_touchStartTime!) <
            const Duration(milliseconds: 350);
    _touchPointer = null;
    _touchStart = null;
    if (!isTap || _isEpubLoading || _currentSelection?.isNotEmpty == true) {
      return;
    }
    final x = event.localPosition.dx / size.width;
    final y = event.localPosition.dy / size.height;
    if (x > 0.35 && x < 0.65 && y > 0.35 && y < 0.65) _toggleControls();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_loadError!),
            ],
          ),
        ),
      );
    }

    if (!_bookDataLoaded) {
      return Scaffold(
        backgroundColor: _getBackgroundColor(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          unawaited(_closeReader());
        } else {
          _saveDebounceTimer?.cancel();
          _saveProgressNow();
        }
      },
      child: Scaffold(
        backgroundColor: _getBackgroundColor(),
        body: Stack(
          children: [
            // EPUB viewer — cached, never rebuilt
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: (_) {
                  _touchPointer = null;
                  _touchStart = null;
                },
                child: RepaintBoundary(child: _getOrBuildEpubViewer()),
              ),
            ),

            // Loading overlay while WebView initialises
            if (_isEpubLoading)
              IgnorePointer(
                child: Container(
                  color: _getBackgroundColor(),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),

            // Top bar
            if (_showControls) _buildTopBar(context, _bookTitle ?? ''),

            // Bottom bar with progress slider
            if (_showControls) _buildBottomBar(context),
          ],
        ),
        drawer: _buildChapterDrawer(context),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Theme helpers
  // ---------------------------------------------------------------------------

  Color _getBackgroundColor() {
    switch (_currentThemeName) {
      case 'Dark':
        return const Color(0xFF121212);
      case 'Sepia':
        return const Color(0xFFF4ECD8);
      default:
        return Colors.white;
    }
  }

  EpubTheme _getTheme() {
    final background = _getBackgroundColor();
    final textColor = _currentThemeName == 'Dark'
        ? '#e0e0e0'
        : (_currentThemeName == 'Sepia' ? '#5d4037' : '#000000');
    final backgroundCss =
        '#${background.toARGB32().toRadixString(16).substring(2)}';
    return EpubTheme.custom(
      backgroundDecoration: BoxDecoration(color: background),
      foregroundColor: _currentThemeName == 'Dark'
          ? Colors.white
          : (_currentThemeName == 'Sepia' ? Colors.brown : Colors.black),
      // Register styles with the rendition's content hook before it measures
      // each chapter, including chapters loaded later during continuous scroll.
      customCss: {
        'body': {
          'padding': '8px 12px !important',
          'line-height': '1.5 !important',
          'word-wrap': 'break-word !important',
          'color': '$textColor !important',
          'background-color': '$backgroundCss !important',
        },
        'p, div, span, td, li, h1, h2, h3, h4, h5, h6, a': {
          'color': '$textColor !important',
        },
        'img': {'max-width': '100% !important', 'height': 'auto !important'},
      },
    );
  }

  // ---------------------------------------------------------------------------
  // EPUB viewer (built once, cached forever)
  // ---------------------------------------------------------------------------

  Widget _getOrBuildEpubViewer() {
    _cachedEpubViewer ??= _buildEpubViewer();
    return _cachedEpubViewer!;
  }

  Widget _buildEpubViewer() {
    return EpubViewer(
      epubController: _epubController!,
      epubSource: EpubSource.fromFile(File(_bookFilePath!)),
      initialCfi: _initialCfi,
      displaySettings: EpubDisplaySettings(
        flow: EpubFlow.scrolled,
        spread: EpubSpread.none,
        snap: false,
        // In flutter_epub_viewer 1.2.8 this also disables Android's custom
        // page-swipe handler, which cancels vertical touchmove events. With
        // snap off, the WebView can scroll naturally without page animation.
        useSnapAnimationAndroid: true,
        allowScriptedContent: true,
        manager: EpubManager.continuous,
        theme: _getTheme(),
        fontSize: _fontSize,
      ),
      selectionContextMenu: ContextMenu(
        menuItems: [ContextMenuItem(id: 1, title: "Define")],
        settings: ContextMenuSettings(hideDefaultSystemContextMenuItems: false),
        onContextMenuActionItemClicked: (item) {
          if (item.id == 1) {
            final text = _currentSelection;
            if (text != null && text.trim().isNotEmpty && mounted) {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent, // For glassmorphism
                builder: (context) => DictionaryDialog(word: text.trim()),
              );
            }
          }
        },
      ),
      onSelection: (text, cfi, rect, viewRect) {
        _currentSelection = text;
      },
      onChaptersLoaded: (chapters) {
        if (mounted) setState(() => _chapters = chapters);
      },
      onDeselection: () => _currentSelection = null,
      onEpubLoaded: () async {
        if (!mounted || !_isEpubLoading || _isPreparingLocationBridge) return;
        _isPreparingLocationBridge = true;
        await _installLocationBridge();
        if (!mounted) return;
        _isPreparingLocationBridge = false;
        setState(() => _isEpubLoading = false);
        _publishProgress();
        if (_locationsReady) unawaited(_refreshLocation());
      },
      onLocationLoaded: () {
        if (!mounted) return;
        _locationsReady = true;
        _publishProgress();
        if (!_isEpubLoading) unawaited(_refreshLocation());
      },
      onRelocated: (location) {
        if (!mounted ||
            _usesDirectLocationEvents ||
            _isEpubLoading ||
            _isPreparingLocationBridge ||
            _isSeeking) {
          return;
        }
        _recordLocation(location);
      },
      onTextSelected: (selection) {
        debugPrint('Selected: ${selection.selectedText}');
      },
    );
  }

  Widget _buildTopBar(BuildContext context, String title) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Builder(
                  builder: (ctx) => IconButton(
                    icon: const Icon(Icons.list, color: Colors.white),
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.text_format, color: Colors.white),
                  onPressed: () => _showTextSettings(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ValueListenableBuilder<_ProgressView>(
              valueListenable: _progressView,
              builder: (context, view, _) => TweenAnimationBuilder<double>(
                tween: Tween<double>(end: view.progress),
                duration: view.animate
                    ? const Duration(milliseconds: 120)
                    : Duration.zero,
                curve: Curves.easeOut,
                builder: (context, progress, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                      ),
                      child: Slider(
                        value: progress.clamp(0.0, 1.0),
                        semanticFormatterCallback: (value) =>
                            '${(value * 100).toStringAsFixed(1)} percent',
                        activeColor: Colors.white,
                        inactiveColor: Colors.white30,
                        onChangeStart: view.canSeek
                            ? (value) {
                                _isSliderDragging = true;
                                _previewProgress = value;
                                _saveDebounceTimer?.cancel();
                                _publishProgress();
                              }
                            : null,
                        onChanged: view.canSeek
                            ? (value) {
                                _previewProgress = value;
                                _publishProgress();
                              }
                            : null,
                        onChangeEnd: view.canSeek ? _seekToProgress : null,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_isSeeking)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        Text(
                          '${(progress * 100).toStringAsFixed(1)}%',
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
    );
  }

  Widget _buildChapterDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Chapters',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _chapters.length,
                itemBuilder: (context, index) {
                  final chapter = _chapters[index];
                  return ListTile(
                    title: Text(chapter.title),
                    leading: const Icon(Icons.bookmark_border),
                    onTap: () {
                      Navigator.pop(context);
                      _epubController?.display(cfi: chapter.href);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTextSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (bottomSheetContext) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reading Settings',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Icon(Icons.format_size),
                    const SizedBox(width: 8),
                    const Text('Font Size'),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _fontSize > 12
                          ? () {
                              setModalState(() => _fontSize -= 2);
                              setState(() {});
                              _saveSettings();
                              _epubController?.setFontSize(
                                fontSize: _fontSize.toDouble(),
                              );
                            }
                          : null,
                    ),
                    Text(
                      '$_fontSize',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _fontSize < 32
                          ? () {
                              setModalState(() => _fontSize += 2);
                              setState(() {});
                              _saveSettings();
                              _epubController?.setFontSize(
                                fontSize: _fontSize.toDouble(),
                              );
                            }
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Theme'),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildThemeButton(
                      context,
                      setModalState,
                      'Light',
                      Colors.white,
                      Colors.black,
                    ),
                    _buildThemeButton(
                      context,
                      setModalState,
                      'Sepia',
                      const Color(0xFFF4ECD8),
                      Colors.brown,
                    ),
                    _buildThemeButton(
                      context,
                      setModalState,
                      'Dark',
                      const Color(0xFF121212),
                      Colors.white,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeButton(
    BuildContext context,
    StateSetter setModalState,
    String name,
    Color bgColor,
    Color textColor,
  ) {
    final isSelected = _currentThemeName == name;
    return GestureDetector(
      onTap: () async {
        setModalState(() => _currentThemeName = name);
        setState(() {});
        _saveSettings();
        _epubController?.updateTheme(theme: _getTheme());
        Navigator.pop(context);
      },
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade400,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: Center(
          child: Text(
            'Aa',
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
