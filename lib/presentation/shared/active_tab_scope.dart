import 'package:flutter/material.dart';

/// Foreground visibility is separate from the lifetime of retained tab state.
class ActiveTabScope extends InheritedWidget {
  final bool isActive;
  const ActiveTabScope({
    super.key,
    required this.isActive,
    required super.child,
  });

  static bool isActiveOf(BuildContext context) =>
      (context.dependOnInheritedWidgetOfExactType<ActiveTabScope>()?.isActive ??
          true) &&
      TickerMode.of(context);

  @override
  bool updateShouldNotify(ActiveTabScope oldWidget) =>
      isActive != oldWidget.isActive;
}
