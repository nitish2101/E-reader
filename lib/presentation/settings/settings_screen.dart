import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/paper_ink_layout.dart';
import '../shared/page_header.dart';
import '../../data/repositories/settings_repository.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../data/repositories/store_repository.dart';
import '../../core/services/cache_config.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = PaperInkLayout.forWidth(
            constraints.maxWidth,
            textScale: MediaQuery.textScalerOf(context).scale(16) / 16,
          );
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                key: const PageStorageKey('settings-scroll'),
                padding: EdgeInsets.fromLTRB(
                  layout.gutter,
                  24,
                  layout.gutter,
                  32,
                ),
                children: [
                  const PageHeader(title: 'Settings'),
                  const SizedBox(height: 24),
                  const _SectionHeader(
                    icon: Icons.palette_outlined,
                    title: 'Appearance',
                  ),
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.dark_mode_outlined),
                      title: Text('Paper & Ink'),
                      subtitle: Text('Warm charcoal · muted olive'),
                    ),
                  ),
                  const _SectionHeader(
                    icon: Icons.store_outlined,
                    title: 'Store & Search',
                  ),
                  Card(
                    child: Column(
                      children: [
                        _SearchSourcesTile(),
                        const Divider(height: 1),
                        _PreferredFormatTile(),
                      ],
                    ),
                  ),
                  const _SectionHeader(
                    icon: Icons.auto_stories_outlined,
                    title: 'Reading',
                  ),
                  Card(child: _AutoSaveProgressTile()),
                  const _SectionHeader(
                    icon: Icons.info_outline,
                    title: 'About',
                  ),
                  Card(
                    child: Column(
                      children: [
                        _AboutTile(),
                        const Divider(height: 1),
                        _ClearCacheTile(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchSourcesTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsRepository>();
    return ValueListenableBuilder(
      valueListenable: Hive.box('settings').listenable(),
      builder: (context, box, _) => Column(
        children: [
          for (final source in BookSource.values)
            SwitchListTile(
              title: Text(source.label),
              subtitle:
                  source == BookSource.gutenberg ||
                      source == BookSource.standardEbooks
                  ? const Text('Classic books with direct EPUB downloads')
                  : null,
              value: switch (source) {
                BookSource.annasArchive => settings.getSearchAnnasArchive(),
                BookSource.libgen => settings.getSearchLibgen(),
                BookSource.gutenberg => settings.getSearchGutenberg(),
                BookSource.standardEbooks => settings.getSearchStandardEbooks(),
              },
              onChanged: (value) {
                final enabled = [
                  settings.getSearchAnnasArchive(),
                  settings.getSearchLibgen(),
                  settings.getSearchGutenberg(),
                  settings.getSearchStandardEbooks(),
                ];
                if (!value && enabled.where((v) => v).length == 1) return;
                switch (source) {
                  case BookSource.annasArchive:
                    settings.setSearchAnnasArchive(value);
                  case BookSource.libgen:
                    settings.setSearchLibgen(value);
                  case BookSource.gutenberg:
                    settings.setSearchGutenberg(value);
                  case BookSource.standardEbooks:
                    settings.setSearchStandardEbooks(value);
                }
              },
            ),
        ],
      ),
    );
  }
}

class _PreferredFormatTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settingsRepo = context.read<SettingsRepository>();

    return ValueListenableBuilder(
      valueListenable: Hive.box('settings').listenable(),
      builder: (context, box, _) {
        final format = settingsRepo.getDownloadFormat();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preferred Format',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Default: ${format.toUpperCase()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'pdf', label: Text('PDF')),
                  ButtonSegment(value: 'epub', label: Text('EPUB')),
                ],
                selected: {format},
                onSelectionChanged: (selected) =>
                    settingsRepo.setDownloadFormat(selected.first),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AutoSaveProgressTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settingsRepo = context.read<SettingsRepository>();

    return ValueListenableBuilder(
      valueListenable: Hive.box('settings').listenable(),
      builder: (context, box, _) {
        final autoSave = settingsRepo.getAutoSaveProgress();

        return SwitchListTile(
          secondary: Icon(
            Icons.save_outlined,
            color: Theme.of(context).colorScheme.secondary,
          ),
          title: const Text('Auto-save Progress'),
          subtitle: const Text('Automatically save reading position'),
          value: autoSave,
          onChanged: (value) {
            settingsRepo.setAutoSaveProgress(value);
          },
        );
      },
    );
  }
}

class _AboutTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.info_outline,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('About E-Reader'),
      subtitle: const Text('Version 1.2.0'),
      onTap: () {
        showAboutDialog(
          context: context,
          applicationName: 'E-Reader',
          applicationVersion: '1.2.0',
          applicationIcon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.auto_stories,
              size: 32,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          applicationLegalese: '© 2026 E-Reader App',
          children: [
            const SizedBox(height: 16),
            const Text(
              'A modern e-reader app for Android that supports PDF and EPUB formats. '
              'Search and download books from Anna\'s Archive, LibGen, and Project Gutenberg.',
            ),
            const SizedBox(height: 16),
            Text(
              'Features:',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '• PDF & EPUB reader\n'
              '• Multiple book sources\n'
              '• Reading progress tracking\n'
              '• Paper & Ink dark appearance\n'
              '• Offline library management',
            ),
          ],
        );
      },
    );
  }
}

class _ClearCacheTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.delete_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      title: const Text('Clear Cache'),
      subtitle: const Text('Remove cached book covers and data'),
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Cache?'),
            content: const Text(
              'This will remove all cached book covers and search results. '
              'Your library and reading progress will not be affected.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () async {
                  final store = context.read<StoreRepository>();
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  store.clearCache();
                  await BookCoverCacheManager().emptyCache();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Cache cleared successfully'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: const Text('Clear'),
              ),
            ],
          ),
        );
      },
    );
  }
}
