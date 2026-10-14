class PaperInkLayout {
  final bool useNavigationRail;
  final double gutter;
  final int libraryColumns;
  final int storeColumns;

  PaperInkLayout.forWidth(double width, {required double textScale})
    : useNavigationRail = width >= 720,
      gutter = width >= 1000
          ? 32
          : width >= 600
          ? 24
          : 16,
      libraryColumns =
          ((width - 32 + 24) / (160 * textScale.clamp(1, 1.6) + 24))
              .floor()
              .clamp(1, 6),
      storeColumns = width >= 840 && textScale < 1.5 ? 2 : 1;
}
