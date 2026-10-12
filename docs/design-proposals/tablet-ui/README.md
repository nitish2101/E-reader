# Proposed tablet UI designs

Status: Paper & Ink, including its dark companion, was approved for planning on 2026-10-13. No application code, dependencies, or configuration has been changed. The implementation plan awaits review before execution.

- [Design specification](../../superpowers/specs/2026-10-13-paper-and-ink-tablet-redesign.md)
- [Implementation plan](../../superpowers/plans/2026-10-13-paper-and-ink-tablet-redesign.md)

## Review

1. **Paper & Ink — recommended:** warm paper, olive accents, serif headings, an airy Library cover shelf, and a Store catalogue with text beside the covers. Charcoal reader appearance shown. Best fit for a distinctive reading-focused identity with low visual clutter.
2. **Quiet Modern:** clear white and cool slate, teal accents, horizontal Library book tiles and a Store cover grid. The most practical choice for scanning titles and authors.
3. **Night Library:** graphite and muted brass, larger book tiles, serif headings and an ivory reader companion. Strongest emphasis on the dark appearance.

Each board shows Library and Store together with representative EPUB reader controls, a missing-cover placeholder, long titles, reading progress, source labels, and an active download with cancellation.

- [Paper & Ink](1-paper-ink.png)
- [Paper & Ink — Dark](1-paper-ink-dark.png): requested dark companion, with warm charcoal surfaces, sage/olive controls, and off-white text; retains the Paper & Ink layouts and book artwork.
- [Quiet Modern](2-quiet-modern.png)
- [Night Library](3-night-library.png)

## Guidance used

- [UI UX Pro Max SKILL.md](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/main/.claude/skills/ui-ux-pro-max/SKILL.md), downloaded into a temporary task folder on 2026-10-13. No global installation or application dependency was added.
- Ran its design-system searches and explicitly queried its Flutter stack guidance for responsive tablet layout, themes, typography, and accessibility.
- Read its Flutter dataset, native app professional rules, and accessibility/touch/performance quick references.
- The design-system engine returned marketing landing-page patterns; a narrower retry still returned a website pattern. No verified native screen-pattern match was found, so those patterns were excluded. Native layouts are proposals grounded in the existing app and its Flutter guidance, rather than claimed database matches.
- The first modern-style result recommended glass effects, which conflicted with the brief; an explicit minimalism search supplied a better-fitting style.
- Retained recommendations relevant to constraints-based layout, ThemeData/ColorScheme, shared widgets, lazy lists, stable keys, semantics, dark/light themes, 48dp Android targets, and a consistent spacing rhythm. Existing BLoCs and GoRouter stay the implementation approach.
- Generated using the built-in image-generation tool. Exact generation prompts and the focused Paper & Ink refinement are retained in prompts.txt.
- The dark Paper & Ink companion was produced by editing the original with the built-in image-generation tool; its exact prompt is retained in prompt-paper-ink-dark.txt.

## Implementation scope after approval

Adapt the existing navigation shell, Library and Store presentation, shared book-cover components, Settings presentation, global themes, and EPUB control overlays. Preserve persistence and the reader location bridge, catalog/download logic, search and filter state, pagination, scroll offsets, and active download state. Keep the reader outside the app shell. Do not introduce a new state-management framework or add tests.

Use responsive constraints: navigation rail at wide tablet widths and the existing three-destination bottom navigation at compact/split-screen widths; preserve cover proportions; reduce columns or switch to single-column tiles before titles and actions become cramped. Retain light/dark/system app appearance and Light/Sepia/Dark reader settings.

## Verification boundaries

These are AI-generated visual proposals, not screenshots of a running Flutter application. Book artwork is illustrative; existing imported/downloaded covers remain the source in the app. The settings panel shown beside the reader is a design-board detail, not a commitment to an always-visible panel. Touch target dimensions, contrast, text scaling, keyboard/screen-reader behavior, portrait/landscape/split-screen adaptation, and empty/error states require actual implementation checks after approval. No analysis, tests, Android build, or emulator checks were run for this image-only phase.
