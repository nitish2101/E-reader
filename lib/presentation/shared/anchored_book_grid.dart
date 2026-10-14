import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keeps the leading book in view when a tablet grid reflows or reorders.
class AnchoredBookGrid extends StatefulWidget {
  final List<String> ids;
  final ScrollController controller;
  final Widget header;
  final Widget empty;
  final Widget? footer;
  final IndexedWidgetBuilder itemBuilder;
  final int columns;
  final double itemExtent;
  final double gutter;
  final String storageKey;
  const AnchoredBookGrid({
    super.key,
    required this.ids,
    required this.controller,
    required this.header,
    required this.empty,
    this.footer,
    required this.itemBuilder,
    required this.columns,
    required this.itemExtent,
    required this.gutter,
    required this.storageKey,
  });
  @override
  State<AnchoredBookGrid> createState() => _AnchoredBookGridState();
}

class _AnchoredBookGridState extends State<AnchoredBookGrid> {
  final _headerKey = GlobalKey();
  int? _columns;
  double? _extent;
  double _headerHeight = 0;
  List<String> _ids = [];
  int _layoutVersion = 0;

  @override
  Widget build(BuildContext context) {
    final changed =
        _columns != widget.columns ||
        _extent != widget.itemExtent ||
        !listEquals(_ids, widget.ids);
    String? anchor;
    int previousIndex = 0;
    double offsetInRow = 0;
    if (_columns != null &&
        _extent != null &&
        _ids.isNotEmpty &&
        widget.controller.hasClients &&
        widget.controller.offset > _headerHeight) {
      final offset = widget.controller.offset - _headerHeight;
      final row = (offset / (_extent! + 24)).floor();
      previousIndex = math.min(row * _columns!, _ids.length - 1);
      anchor = _ids[previousIndex];
      offsetInRow = offset % (_extent! + 24);
    }
    _columns = widget.columns;
    _extent = widget.itemExtent;
    _ids = [...widget.ids];
    final previousHeaderHeight = _headerHeight;
    final version = ++_layoutVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || version != _layoutVersion) return;
      final box = _headerKey.currentContext?.findRenderObject();
      _headerHeight = box is RenderBox ? box.size.height : 0;
      final headerChanged = (_headerHeight - previousHeaderHeight).abs() > 0.5;
      if ((changed || headerChanged) &&
          anchor != null &&
          widget.controller.hasClients &&
          widget.ids.isNotEmpty) {
        final found = widget.ids.indexOf(anchor);
        final index = found < 0
            ? math.min(previousIndex, widget.ids.length - 1)
            : found;
        final target =
            _headerHeight +
            (index ~/ widget.columns) * (widget.itemExtent + 24) +
            math.min(offsetInRow, widget.itemExtent);
        widget.controller.jumpTo(
          target.clamp(0, widget.controller.position.maxScrollExtent),
        );
      }
    });
    return CustomScrollView(
      key: PageStorageKey(widget.storageKey),
      controller: widget.controller,
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(key: _headerKey, child: widget.header),
        ),
        if (widget.ids.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: widget.empty)
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(widget.gutter, 0, widget.gutter, 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: widget.columns,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
                mainAxisExtent: widget.itemExtent,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => RepaintBoundary(
                  key: ValueKey(widget.ids[index]),
                  child: widget.itemBuilder(context, index),
                ),
                childCount: widget.ids.length,
                findChildIndexCallback: (key) =>
                    key is ValueKey<String> && widget.ids.contains(key.value)
                    ? widget.ids.indexOf(key.value)
                    : null,
              ),
            ),
          ),
        if (widget.footer != null) SliverToBoxAdapter(child: widget.footer),
      ],
    );
  }
}
