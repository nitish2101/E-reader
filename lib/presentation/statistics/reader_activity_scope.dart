import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/statistics/reading_tracker.dart';

final readingRouteObserver = RouteObserver<ModalRoute<dynamic>>();

/// The reader owns readiness; the scope owns foreground/route visibility.
class ReaderActivityController extends ChangeNotifier {
  bool _loaded = false;
  bool _blocked = false;
  bool _navigating = false;
  bool _disposed = false;
  int _navigationVersion = 0;
  VoidCallback? _onInteraction;
  bool get ready => _loaded && !_blocked && !_navigating;
  void setLoaded(bool loaded) {
    if (_loaded == loaded) return;
    _loaded = loaded;
    notifyListeners();
  }

  void setBlocked(bool blocked) {
    if (_blocked == blocked) return;
    _blocked = blocked;
    notifyListeners();
  }

  /// New page seeks can cancel animation futures without completing them.
  /// Only the latest request releases the clock; abandoned futures are bounded.
  Future<void> navigate(Future<void> Function() action) async {
    final version = ++_navigationVersion;
    _navigating = true;
    notifyListeners();
    try {
      await action().timeout(const Duration(seconds: 2));
    } finally {
      if (!_disposed && version == _navigationVersion) {
        _navigating = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _navigationVersion++;
    super.dispose();
  }

  void interact() => _onInteraction?.call();
}

class ReaderActivityScope extends StatefulWidget {
  final String bookId;
  final ReaderActivityController controller;
  final Widget child;
  const ReaderActivityScope({
    super.key,
    required this.bookId,
    required this.controller,
    required this.child,
  });
  @override
  State<ReaderActivityScope> createState() => _ReaderActivityScopeState();
}

class _ReaderActivityScopeState extends State<ReaderActivityScope>
    with WidgetsBindingObserver, RouteAware {
  ReadingLease? _lease;
  ModalRoute<dynamic>? _route;
  bool _visible = true;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    widget.controller.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lease ??= context.read<ReadingTracker>().open(widget.bookId);
    widget.controller._onInteraction = _lease!.interact;
    final route = ModalRoute.of(context);
    if (_route != route) {
      readingRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) readingRouteObserver.subscribe(this, route);
    }
    _visible = route?.isCurrent ?? true;
    _sync();
  }

  void _sync() =>
      _lease?.setActive(_foreground && _visible && widget.controller.ready);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void didPushNext() {
    _visible = false;
    _sync();
  }

  @override
  void didPopNext() {
    _visible = true;
    _sync();
  }

  @override
  void didPop() {
    _visible = false;
    _sync();
  }

  @override
  void dispose() {
    readingRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_sync);
    widget.controller._onInteraction = null;
    _lease?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => widget.controller.interact(),
    onPointerMove: (_) => widget.controller.interact(),
    onPointerSignal: (_) => widget.controller.interact(),
    child: widget.child,
  );
}
