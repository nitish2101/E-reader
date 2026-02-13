import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:hive/hive.dart';

import '../../data/repositories/book_repository.dart';

/// EPUB reader screen — completely Bloc-free during reading.
///
/// Architecture:
/// - Book data loaded synchronously from Hive (no Bloc needed)
/// - Progress tracked 100% locally — no state emissions, no rebuilds
/// - Saves to repository on: scroll-stop debounce, back button,
///   app lifecycle pause, and dispose
/// - Resume uses ONLY `initialCfi` parameter — no secondary navigation
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
  bool _hasDirtyProgress = false;
  bool _hasResumedPosition = false; // Guard: navigate to saved CFI only once

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
    _progress = book.lastReadProgress;
    _currentCfi = book.lastReadCfi;
    // Only use CFI if it's a valid epubcfi string
    _initialCfi = (book.lastReadCfi != null &&
            book.lastReadCfi!.isNotEmpty &&
            book.lastReadCfi!.startsWith('epubcfi('))
        ? book.lastReadCfi
        : null;
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
      _saveProgressNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveDebounceTimer?.cancel();
    _saveProgressNow();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Immediately persist current progress to Hive (no Bloc)
  void _saveProgressNow() {
    if (!_hasDirtyProgress) return;
    if (_currentCfi == null || _currentCfi!.isEmpty) return;
    _hasDirtyProgress = false;
    try {
      _bookRepository.updateReadingProgress(
        bookId: widget.bookId,
        page: 0,
        progress: _progress,
        cfi: _currentCfi,
      );
    } catch (e) {
      debugPrint('Failed to save progress: $e');
    }
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
    setState(() => _showControls = !_showControls);
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
      canPop: true,
      onPopInvoked: (bool didPop) {
        if (didPop) {
          _saveDebounceTimer?.cancel();
          _saveProgressNow();
        }
      },
      child: Scaffold(
        backgroundColor: _getBackgroundColor(),
        body: Stack(
          children: [
            // EPUB viewer — cached, never rebuilt
            Positioned.fill(child: _getOrBuildEpubViewer()),

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
    switch (_currentThemeName) {
      case 'Dark':
        return EpubTheme.custom(
          backgroundDecoration: const BoxDecoration(color: Color(0xFF121212)),
          foregroundColor: Colors.white,
        );
      case 'Sepia':
        return EpubTheme.custom(
          backgroundDecoration: const BoxDecoration(color: Color(0xFFF4ECD8)),
          foregroundColor: Colors.brown,
        );
      default:
        return EpubTheme.light();
    }
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
      initialCfi: _initialCfi, // The ONLY way we set the start position
      displaySettings: EpubDisplaySettings(
        flow: EpubFlow.scrolled,
        spread: EpubSpread.none,
        snap: false,
        allowScriptedContent: true,
        manager: EpubManager.continuous,
        theme: _getTheme(),
        fontSize: _fontSize,
      ),
      onChaptersLoaded: (chapters) {
        if (mounted) setState(() => _chapters = chapters);
      },
      onEpubLoaded: () async {
        // Guard: only run resume logic on the very first load.
        // In continuous scroll mode, onEpubLoaded fires for every
        // new section/iframe — without this guard, it would snap
        // the user back to the initial position on every scroll.
        if (_hasResumedPosition) return;
        _hasResumedPosition = true;

        try {
          await _applyCustomStyles();
        } catch (_) {}

        if (mounted) setState(() => _isEpubLoading = false);
      },
      onRelocated: (location) {
        // ──────────────────────────────────────────────────────────
        // ZERO rebuilds here. Just store values and schedule a save.
        // ──────────────────────────────────────────────────────────
        _currentCfi = location.startCfi;
        _progress = location.progress;
        _hasDirtyProgress = true;
        _scheduleSave();

        // Update the slider only if the control overlay is visible
        if (_showControls && mounted && !_isSliderDragging) {
          setState(() {}); // Rebuilds only the overlay, never the cached viewer
        }
      },
      onTextSelected: (selection) {
        debugPrint('Selected: ${selection.selectedText}');
      },
      onTouchUp: (x, y) {
        if (x > 0.35 && x < 0.65 && y > 0.35 && y < 0.65) {
          _toggleControls();
        }
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
                  onPressed: () => Navigator.pop(context),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  ),
                  child: Slider(
                    value: _progress.clamp(0.0, 1.0),
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                    onChangeStart: (value) {
                      _isSliderDragging = true;
                      _saveDebounceTimer?.cancel();
                    },
                    onChanged: (value) {
                      setState(() {
                        _progress = value;
                      });
                    },
                    onChangeEnd: (value) {
                      _isSliderDragging = false;
                      _epubController?.toProgressPercentage(value);
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${(_progress * 100).toInt()}%',
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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
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
                      onPressed: _fontSize > 12 ? () {
                        setModalState(() => _fontSize -= 2);
                        setState(() {});
                        _saveSettings();
                        _epubController?.setFontSize(fontSize: _fontSize.toDouble());
                      } : null,
                    ),
                    Text('$_fontSize', style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _fontSize < 32 ? () {
                        setModalState(() => _fontSize += 2);
                        setState(() {});
                        _saveSettings();
                        _epubController?.setFontSize(fontSize: _fontSize.toDouble());
                      } : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Theme'),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildThemeButton(context, setModalState, 'Light', Colors.white, Colors.black),
                    _buildThemeButton(context, setModalState, 'Sepia', const Color(0xFFF4ECD8), Colors.brown),
                    _buildThemeButton(context, setModalState, 'Dark', const Color(0xFF121212), Colors.white),
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
        // Reapply custom styles with new theme colors after a short delay
        Future.delayed(const Duration(milliseconds: 300), () async {
          try {
            await _applyCustomStyles();
            debugPrint('Custom styles reapplied for new theme');
          } catch (e) {
            debugPrint('Failed to reapply custom styles: $e');
          }
        });
        Navigator.pop(context);
      },
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
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

  Future<void> _applyCustomStyles() async {
    // Get theme colors
    final isDarkTheme = _currentThemeName == 'Dark';
    final isSepiaTheme = _currentThemeName == 'Sepia';
    final textColor = isDarkTheme ? '#e0e0e0' : (isSepiaTheme ? '#5d4037' : '#000000');
    final bgColor = isDarkTheme ? '#121212' : (isSepiaTheme ? '#F4ECD8' : '#ffffff');
    
    // Build CSS as a Dart string to avoid JavaScript template literal issues
    final cssRules = '''
      body {
        padding: 8px 12px !important;
        line-height: 1.5 !important;
        word-wrap: break-word !important;
        color: $textColor !important;
        background-color: $bgColor !important;
      }
      p, div, span, td, li, h1, h2, h3, h4, h5, h6, a {
        color: $textColor !important;
      }
      img {
        max-width: 100% !important;
        height: auto !important;
      }
    ''';
    
    // Inject styles using a MutationObserver so new iframes (loaded during
    // continuous scroll) also get styled automatically.
    final js = '''
      (function() {
        try {
          var cssText = ${_escapeJsString(cssRules)};
          
          var injectFrame = function(doc) {
            if (!doc || !doc.head) return;
            // Avoid duplicate injection
            if (doc.querySelector('style[data-ereader-theme]')) {
              doc.querySelector('style[data-ereader-theme]').remove();
            }
            var style = doc.createElement('style');
            style.type = 'text/css';
            style.setAttribute('data-ereader-theme', 'true');
            style.appendChild(doc.createTextNode(cssText));
            doc.head.appendChild(style);
          };
          
          var processIframe = function(iframe) {
            try {
              if (iframe.contentDocument && iframe.contentDocument.head) {
                injectFrame(iframe.contentDocument);
              }
            } catch(e) {}
            // Also inject when iframe reloads
            iframe.removeEventListener('load', iframe._ereaderLoadHandler);
            iframe._ereaderLoadHandler = function() {
              try { injectFrame(this.contentDocument); } catch(e) {}
            };
            iframe.addEventListener('load', iframe._ereaderLoadHandler);
          };
          
          // Style all existing iframes
          var frames = document.querySelectorAll('iframe');
          for (var i = 0; i < frames.length; i++) {
            processIframe(frames[i]);
          }
          
          // Disconnect any previous observer we set up
          if (window._ereaderObserver) {
            window._ereaderObserver.disconnect();
          }
          
          // Watch for new iframes added to the DOM (continuous scroll adds them)
          window._ereaderObserver = new MutationObserver(function(mutations) {
            for (var m = 0; m < mutations.length; m++) {
              var added = mutations[m].addedNodes;
              for (var n = 0; n < added.length; n++) {
                var node = added[n];
                if (node.nodeType !== 1) continue;
                if (node.tagName === 'IFRAME') {
                  processIframe(node);
                }
                // Also check children (iframe might be nested in a container)
                var nested = node.querySelectorAll ? node.querySelectorAll('iframe') : [];
                for (var j = 0; j < nested.length; j++) {
                  processIframe(nested[j]);
                }
              }
            }
          });
          
          window._ereaderObserver.observe(document.body, {
            childList: true,
            subtree: true
          });
          
        } catch(e) { 
          console.log('Style injection error: ' + e.toString()); 
        }
      })();
    ''';
    
    try {
      await _epubController?.webViewController?.evaluateJavascript(source: js);
    } catch (e) {
      debugPrint('Failed to apply custom styles: $e');
    }
  }
  
  String _escapeJsString(String str) {
    return '"' + str
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t') + '"';
  }
}

