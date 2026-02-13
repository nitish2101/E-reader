import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/theme_cubit.dart';
import '../../data/repositories/settings_repository.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Theme Section
          _SectionHeader(
            icon: Icons.palette_outlined,
            title: 'Appearance',
          ),
          _ThemeSettingTile(),
          const Divider(indent: 16, endIndent: 16),

          // Store Settings Section
          _SectionHeader(
            icon: Icons.store_outlined,
            title: 'Store & Search',
          ),
          _SearchSourcesTile(),
          _PreferredFormatTile(),
          const Divider(indent: 16, endIndent: 16),

          // Reader Settings Section
          _SectionHeader(
            icon: Icons.auto_stories_outlined,
            title: 'Reading',
          ),
          _AutoSaveProgressTile(),
          const Divider(indent: 16, endIndent: 16),

          // About Section
          _SectionHeader(
            icon: Icons.info_outline,
            title: 'About',
          ),
          _AboutTile(),
          _ClearCacheTile(),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
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

class _ThemeSettingTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, state) {
        return ListTile(
          leading: Icon(
            _getThemeIcon(state.themeMode),
            color: Theme.of(context).colorScheme.secondary,
          ),
          title: const Text('Theme Mode'),
          subtitle: Text(_getThemeLabel(state.themeMode)),
          trailing: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode, size: 16),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto, size: 16),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode, size: 16),
              ),
            ],
            selected: {state.themeMode},
            onSelectionChanged: (Set<ThemeMode> selected) {
              context.read<ThemeCubit>().setThemeMode(selected.first);
            },
          ),
        );
      },
    );
  }

  IconData _getThemeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.brightness_auto;
    }
  }

  String _getThemeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light mode active';
      case ThemeMode.dark:
        return 'Dark mode active';
      case ThemeMode.system:
        return 'Follows system settings';
    }
  }
}

class _SearchSourcesTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.archive,
        color: Colors.purple[400],
      ),
      title: const Text('Search Source'),
      subtitle: const Text('Using Anna\'s Archive'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.purple.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Active',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
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

        return ListTile(
          leading: Icon(
            Icons.file_download_outlined,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          title: const Text('Preferred Format'),
          subtitle: Text('Default: ${format.toUpperCase()}'),
          trailing: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'pdf',
                label: Text('PDF'),
              ),
              ButtonSegment(
                value: 'epub',
                label: Text('EPUB'),
              ),
            ],
            selected: {format},
            onSelectionChanged: (Set<String> selected) {
              settingsRepo.setDownloadFormat(selected.first);
            },
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
      subtitle: const Text('Version 1.0.0'),
      onTap: () {
        showAboutDialog(
          context: context,
          applicationName: 'E-Reader',
          applicationVersion: '1.0.0',
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
              'Search and download books from Anna\'s Archive and LibGen.',
            ),
            const SizedBox(height: 16),
            Text(
              'Features:',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            const Text('• PDF & EPUB reader\n'
                '• Multiple book sources\n'
                '• Reading progress tracking\n'
                '• Dark & Light themes\n'
                '• Offline library management'),
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
                onPressed: () {
                  // TODO: Implement cache clearing
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
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
