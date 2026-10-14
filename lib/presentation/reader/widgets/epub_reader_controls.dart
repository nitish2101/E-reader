import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

ThemeData readerControlTheme(String name) {
  if (name == 'Dark') return AppTheme.darkTheme;
  final sepia = name == 'Sepia';
  final background = sepia ? const Color(0xFFF4ECD8) : const Color(0xFFF8F5EE);
  final foreground = sepia ? const Color(0xFF5D4037) : const Color(0xFF232720);
  // These are the existing EPUB reading-color choices, independent of app chrome.
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFF526343),
    brightness: Brightness.light,
    surface: background,
    onSurface: foreground,
    primary: const Color(0xFF526343),
    onPrimary: Colors.white,
    onSurfaceVariant: foreground,
    outline: const Color(0xFF858A7D),
    outlineVariant: const Color(0xFFD6D7CD),
  );
  return AppTheme.darkTheme.copyWith(
    brightness: Brightness.light,
    colorScheme: colors,
    scaffoldBackgroundColor: background,
    textTheme: AppTheme.darkTheme.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    ),
    iconTheme: IconThemeData(color: foreground, size: 24),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size(48, 48),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: colors.primary,
      thumbColor: colors.primary,
      inactiveTrackColor: colors.outline,
      trackHeight: 4,
    ),
  );
}

class EpubTopControls extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onChapters;
  final VoidCallback onTextSettings;
  const EpubTopControls({
    super.key,
    required this.title,
    required this.onBack,
    required this.onChapters,
    required this.onTextSettings,
  });
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= 600 &&
                MediaQuery.textScalerOf(context).scale(16) <= 24;
            return Row(
              children: [
                IconButton(
                  tooltip: 'Back to library',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBack,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                if (wide) ...[
                  TextButton.icon(
                    onPressed: onChapters,
                    icon: const Icon(Icons.list),
                    label: const Text('Chapters'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onTextSettings,
                    icon: const Icon(Icons.text_format),
                    label: const Text('Text'),
                  ),
                ] else ...[
                  IconButton(
                    tooltip: 'Chapters',
                    icon: const Icon(Icons.list),
                    onPressed: onChapters,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Reading settings',
                    icon: const Icon(Icons.text_format),
                    onPressed: onTextSettings,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}

class EpubProgressControls extends StatelessWidget {
  final double progress;
  final bool isSeeking;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  const EpubProgressControls({
    super.key,
    required this.progress,
    required this.isSeeking,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final slider = Slider(
      key: ValueKey(onChanged != null),
      value: progress.clamp(0, 1),
      semanticFormatterCallback: (value) =>
          '${(value * 100).toStringAsFixed(1)} percent',
      onChangeStart: onChangeStart,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
    );
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isSeeking) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Text(
          '${(progress * 100).toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 24, 8),
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 600
                ? Row(
                    children: [
                      Expanded(child: slider),
                      const SizedBox(width: 16),
                      label,
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      slider,
                      Align(alignment: Alignment.centerRight, child: label),
                      const SizedBox(height: 8),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
