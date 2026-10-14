import 'package:flutter/material.dart';

class BookProgress extends StatelessWidget {
  final double progress;
  final String label;
  const BookProgress({super.key, required this.progress, required this.label});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(
        child: LinearProgressIndicator(
          value: progress.isFinite ? progress.clamp(0, 1) : 0,
          minHeight: 4,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
