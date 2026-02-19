import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../widgets/app_card.dart';
import '../widgets/section_header.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Settings',
          subtitle: 'Device preferences, updates, and workspace paths.',
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.system_update_alt_rounded,
                          color: AppPalette.primary,
                        ),
                        const SizedBox(width: 8),
                        Text('Updates', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _settingRow('Channel', 'Stable (GitHub releases)'),
                    _settingRow('Auto-download', 'Enabled on first launch'),
                    _settingRow(
                      'Latest release',
                      appState.latestUpdate?.tag ?? 'Not checked',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: appState.checkForUpdates,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Check for updates'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: appState.latestUpdate == null
                          ? null
                          : appState.installLatestUpdate,
                      icon: const Icon(Icons.system_update_alt_rounded),
                      label: const Text('Install latest core'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: appState.isBusy
                          ? null
                          : appState.downloadLatestCore,
                      icon: const Icon(Icons.cloud_download_rounded),
                      label: const Text('Download stable core'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: appState.isBusy
                          ? null
                          : appState.downloadExperimentalCore,
                      icon: const Icon(Icons.science_rounded),
                      label: const Text('Download experimental core'),
                    ),
                    if (appState.isBusy)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(
                              minHeight: 4,
                              value: appState.downloadProgress,
                            ),
                            if (appState.downloadProgressText != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  appState.downloadProgressText!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.hintColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (appState.statusMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          appState.statusMessage!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color:
                                appState.statusMessage!.toLowerCase().contains(
                                  'failed',
                                )
                                ? AppPalette.danger
                                : AppPalette.secondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.usb_rounded, color: AppPalette.secondary),
                        const SizedBox(width: 8),
                        Text(
                          'Device & Paths',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _settingRow(
                      'Client binary',
                      appState.coreInfo.path ?? 'Not available',
                    ),
                    _settingRow('Core source', appState.coreInfo.source.name),
                    _settingRow(
                      'Default serial port',
                      appState.selectedPort?.displayName ?? 'Not selected',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: appState.refreshPorts,
                          icon: const Icon(Icons.usb_rounded),
                          label: const Text('Refresh ports'),
                        ),
                        OutlinedButton.icon(
                          onPressed: appState.importCoreFromFile,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('Import core binary'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.palette_rounded, color: AppPalette.accent),
                        const SizedBox(width: 8),
                        Text('Appearance', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ThemeMode>(
                      initialValue: appState.themeMode,
                      decoration: const InputDecoration(
                        labelText: 'Theme',
                        prefixIcon: Icon(Icons.dark_mode_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ThemeMode.system,
                          child: Text('System'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.light,
                          child: Text('Light'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.dark,
                          child: Text('Dark'),
                        ),
                      ],
                      onChanged: (mode) {
                        if (mode != null) {
                          appState.setThemeMode(mode);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<AccentPalette>(
                      initialValue: appState.accentPalette,
                      decoration: const InputDecoration(
                        labelText: 'Palette',
                        prefixIcon: Icon(Icons.palette_rounded),
                      ),
                      items: AccentPalette.values
                          .map(
                            (palette) => DropdownMenuItem(
                              value: palette,
                              child: Text(AppPalette.paletteLabel(palette)),
                            ),
                          )
                          .toList(),
                      onChanged: (palette) {
                        if (palette != null) {
                          appState.setAccentPalette(palette);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: appState.reopenOnboarding,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Show Help Overlay'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: appState.openSupportLink,
                      icon: const Icon(Icons.coffee_rounded),
                      label: const Text('Support Project'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
