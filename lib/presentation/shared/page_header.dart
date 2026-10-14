import 'package:flutter/material.dart';

class PageHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const PageHeader({super.key, required this.title, this.actions = const []});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      );
      final buttons = Wrap(spacing: 8, runSpacing: 8, children: actions);
      if (constraints.maxWidth < 580 ||
          MediaQuery.textScalerOf(context).scale(16) > 24) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            if (actions.isNotEmpty) ...[const SizedBox(height: 16), buttons],
            const SizedBox(height: 16),
            const Divider(height: 1),
          ],
        );
      }
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 16),
              buttons,
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
        ],
      );
    },
  );
}
