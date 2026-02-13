import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:hive/hive.dart';

import '../../data/repositories/book_repository.dart';
import 'bloc/reader_bloc.dart';

class EpubReaderScreen extends StatelessWidget {
  final String bookId;

  const EpubReaderScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ReaderBloc(
        bookRepository: context.read<BookRepository>(),
      )..add(LoadBook(bookId)),
      child: _EpubReaderContent(bookId: bookId),
    );
  }
}

class _EpubReaderContent extends StatefulWidget {
  final String bookId;
  const _EpubReaderContent({required this.bookId});

  @override
  State<_EpubReaderContent> createState() => _EpubReaderContentState();
}

class _EpubReaderContentState extends State<_EpubReaderContent> {
  EpubController? _epubController;
  Timer? _autoSaveTimer;
  Timer? _progressDebounceTimer;
  bool _showControls = false;
  double _progress = 0.0;
  double _pendingProgress = 0.0;
  String? _lastCfi;
  String? _pendingCfi;
  String? _initialCfi; // Store initial CFI once, don't re-read from state
  bool _initialCfiSet = false;
  bool _hasNavigatedToSavedPosition = false; // Only navigate to saved CFI once
  bool _epubFullyLoaded = false; // Track if epub has loaded at least once
  Widget? _cachedEpubViewer; // Cache the viewer to prevent rebuilds
  List<EpubChapter> _chapters = [];
  bool _isLoading = true;
  bool _isSliderDragging = false;
  String? _bookFilePath;
  late BookRepository _bookRepository; // Cached ref for dispose

  // Settings
  int _fontSize = 18;
  String _currentThemeName = 'Light';

  // Track user scroll activity to prevent navigation jumps
  DateTime? _lastUserScrollTime;
  static const _scrollCooldownMs = 2000; // 2 second cooldown after scroll

  @override
  void initState() {
    super.initState();
    _epubController = EpubController();

    // Load saved settings
    _loadSavedSettings();

    // Hide system UI for immersive reading
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Auto-save every 10 seconds — context now has access to ReaderBloc
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _saveProgressToBloc();
      }
    });
  }

  void _loadSavedSettings() {
    final settingsBox = Hive.box('settings');
    // Load globally saved theme and font size - these persist across all books
    final savedTheme = settingsBox.get('readerTheme', defaultValue: 'Light');
    final savedFontSize = settingsBox.get('readerFontSize', defaultValue: 18);
    setState(() {
      _currentThemeName = savedTheme;
      _fontSize = savedFontSize;
    });
  }

  void _saveSettings() {
    final settingsBox = Hive.box('settings');
    settingsBox.put('readerTheme', _currentThemeName);
    settingsBox.put('readerFontSize', _fontSize);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache repository reference so it's available in dispose()
    _bookRepository = context.read<BookRepository>();
  }

  @override
  void dispose() {
    // Cancel debounce timer so pending values don't fire after dispose
    _progressDebounceTimer?.cancel();
    _autoSaveTimer?.cancel();

    // Flush pending progress and save directly to repository
    // (bloc events may not process in time during dispose)
    if (_pendingCfi != null) {
      _lastCfi = _pendingCfi;
      _progress = _pendingProgress > 0 ? _pendingProgress : _progress;
    }
    if (_lastCfi != null && _lastCfi!.isNotEmpty) {
      try {
        _bookRepository.updateReadingProgress(
          bookId: widget.bookId,
          page: 0,
          progress: _progress,
          cfi: _lastCfi,
        );
        debugPrint('Progress saved on dispose: cfi=$_lastCfi, progress=$_progress');
      } catch (e) {
        debugPrint('Failed to save progress on dispose: $e');
      }
    }

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Save current progress to the bloc (which persists to Hive)
  void _saveProgressToBloc() {
    try {
      // Flush any pending debounced progress to the bloc first
      if (_pendingCfi != null) {
        _lastCfi = _pendingCfi;
        _progress = _pendingProgress > 0 ? _pendingProgress : _progress;
        _pendingCfi = null;
        context.read<ReaderBloc>().add(UpdateEpubProgress(
          cfi: _lastCfi ?? '',
          progress: _progress,
        ));
      }
      context.read<ReaderBloc>().add(SaveProgress());
      debugPrint('Progress save triggered: cfi=$_lastCfi, progress=$_progress');
    } catch (e) {
      debugPrint('Failed to trigger progress save: $e');
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ReaderBloc, ReaderState>(
      listener: (context, state) {
        // Capture the initial CFI only once when the book first loads
        if (!_initialCfiSet && state is ReaderLoaded) {
          _initialCfi = state.cfi;
          _initialCfiSet = true;
          _bookFilePath = state.book.localPath;
          debugPrint('Initial CFI captured: $_initialCfi');
          if (state.progress > 0) {
            setState(() {
              _progress = state.progress;
            });
          }
        }
      },
      builder: (context, state) {
        if (state is ReaderLoading) {
          return Scaffold(
            backgroundColor: _getBackgroundColor(),
            body: const Center(child: CircularProgressIndicator()),
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

          return Scaffold(
            backgroundColor: _getBackgroundColor(),
            body: Stack(
              children: [
                // EPUB Viewer — built only once, cached to prevent rebuilds
                Positioned.fill(
                  child: _bookFilePath != null
                      ? _getOrBuildEpubViewer(context)
                      : const Center(child: CircularProgressIndicator()),
                ),

                // Loading overlay
                if (_isLoading)
                  IgnorePointer(
                    child: Container(
                      color: _getBackgroundColor(),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),

                // Top bar (only when controls visible)
                if (_showControls) _buildTopBar(context, book.title),

                // Bottom bar (only when controls visible)
                if (_showControls) _buildBottomBar(context),
              ],
            ),
            drawer: _buildChapterDrawer(context),
          );
        }

        return Scaffold(
          backgroundColor: _getBackgroundColor(),
          body: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

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

  /// Return the cached viewer, or build it once on first call.
  Widget _getOrBuildEpubViewer(BuildContext context) {
    _cachedEpubViewer ??= _buildEpubViewer(context, _bookFilePath!, _initialCfi);
    return _cachedEpubViewer!;
  }

  Widget _buildEpubViewer(BuildContext context, String filePath, String? initialCfi) {
    String? validCfi;
    if (initialCfi != null && initialCfi.isNotEmpty && initialCfi.startsWith('epubcfi(')) {
      validCfi = initialCfi;
    }

    return EpubViewer(
      epubController: _epubController!,
      epubSource: EpubSource.fromFile(File(filePath)),
      initialCfi: validCfi,
      displaySettings: EpubDisplaySettings(
        flow: EpubFlow.scrolled,
        spread: EpubSpread.none,
        snap: false, // Disable snap for free vertical scrolling
        allowScriptedContent: true, // Scripts needed for proper epub rendering
        manager: EpubManager.continuous,
        theme: _getTheme(),
        fontSize: _fontSize,
      ),
      onChaptersLoaded: (chapters) {
        if (mounted) {
          setState(() {
            _chapters = chapters;
          });
        }
      },
      onEpubLoaded: () async {
        debugPrint('EPUB loaded successfully (first=${ !_epubFullyLoaded })');
        if (_epubFullyLoaded) return; // Ignore subsequent calls
        _epubFullyLoaded = true;

        // Wait for the EPUB renderer to fully stabilize
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          await _applyCustomStyles();
          debugPrint('Custom styles applied');
        } catch (e) {
          debugPrint('Failed to apply custom styles: $e');
        }
        // Explicitly navigate to the saved CFI after load to ensure
        // resume works reliably (initialCfi can race with location generation
        // in scrolled-doc + continuous mode).
        // Skip navigation if user is actively scrolling to prevent jump-backs.
        final isUserScrolling = _lastUserScrollTime != null &&
            DateTime.now().difference(_lastUserScrollTime!).inMilliseconds < _scrollCooldownMs;
        
        if (!_hasNavigatedToSavedPosition && 
            validCfi != null && 
            validCfi!.isNotEmpty &&
            !isUserScrolling) {
          _hasNavigatedToSavedPosition = true;
          try {
            debugPrint('Navigating to saved CFI: $validCfi');
            await Future.delayed(const Duration(milliseconds: 300));
            _epubController?.display(cfi: validCfi!);
          } catch (e) {
            debugPrint('Failed to navigate to saved CFI: $e');
          }
        } else if (isUserScrolling) {
          debugPrint('Skipping navigation to CFI - user is actively scrolling');
        }
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      },
      onRelocated: (location) {
        // Track user scroll activity
        _lastUserScrollTime = DateTime.now();

        // Store pending values immediately for later save
        _pendingCfi = location.startCfi;
        _pendingProgress = location.progress;

        // Cancel any existing debounce timer
        _progressDebounceTimer?.cancel();

        // Longer debounce to avoid ghost jumps during active scrolling
        _progressDebounceTimer = Timer(const Duration(milliseconds: 500), () {
          if (!mounted || _isSliderDragging) return;

          _lastCfi = _pendingCfi;
          final newProgress = _pendingProgress;

          // Only update Bloc/UI if progress changed significantly (1%+)
          // This prevents jitter from tiny scroll adjustments
          if ((newProgress - _progress).abs() > 0.01) {
            _progress = newProgress;
            // Update bloc silently without triggering full rebuild
            context.read<ReaderBloc>().add(UpdateEpubProgress(
              cfi: _lastCfi ?? '',
              progress: newProgress,
            ));
            // Only update slider if controls are visible
            if (_showControls) {
              setState(() {});
            }
          }
        });
      },
      onTextSelected: (selection) {
        debugPrint('Selected: ${selection.selectedText}');
      },
      // Handle tap to toggle controls
      onTouchUp: (x, y) {
        // Tap in the middle 30% of screen toggles controls
        // x and y are normalized (0.0 to 1.0)
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
                      _progressDebounceTimer?.cancel();
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

