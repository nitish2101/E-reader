import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/paper_ink_layout.dart';
import '../shared/active_tab_scope.dart';
import '../statistics/reader_activity_scope.dart';

class HomeScreen extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const HomeScreen({super.key, required this.navigationShell});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, RouteAware {
  ModalRoute<dynamic>? _route;
  bool _visible = true;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      readingRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) readingRouteObserver.subscribe(this, route);
    }
    _visible = route?.isCurrent ?? true;
  }

  @override
  void didPushNext() => setState(() => _visible = false);
  @override
  void didPopNext() => setState(() => _visible = true);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    readingRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _select(int index) => widget.navigationShell.goBranch(index);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final layout = PaperInkLayout.forWidth(
        constraints.maxWidth,
        textScale: scale,
      );
      final colors = Theme.of(context).colorScheme;
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Row(
            children: [
              layout.useNavigationRail
                  ? Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: colors.outlineVariant),
                        ),
                      ),
                      child: NavigationRail(
                        minWidth: 80 * scale.clamp(1, 1.5),
                        selectedIndex: widget.navigationShell.currentIndex,
                        onDestinationSelected: _select,
                        labelType: NavigationRailLabelType.all,
                        leading: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Icon(
                            Icons.menu_book_outlined,
                            color: colors.primary,
                          ),
                        ),
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.library_books_outlined),
                            label: Text('Library'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.store_outlined),
                            label: Text('Store'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings_outlined),
                            label: Text('Settings'),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
              Expanded(
                child: ActiveTabScope(
                  isActive: _visible && _foreground,
                  child: widget.navigationShell,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: layout.useNavigationRail
            ? null
            : Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: NavigationBar(
                  height: 80 + (scale - 1).clamp(0, 1) * 24,
                  selectedIndex: widget.navigationShell.currentIndex,
                  onDestinationSelected: _select,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.library_books_outlined),
                      label: 'Library',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.store_outlined),
                      label: 'Store',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      label: 'Settings',
                    ),
                  ],
                ),
              ),
      );
    },
  );
}
