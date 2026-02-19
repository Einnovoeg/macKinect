import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../widgets/app_card.dart';
import '../widgets/section_header.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.connected, this.portName});

  final bool connected;
  final String? portName;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mutedSurface = isDark
        ? const Color(0xFF15212E)
        : AppPalette.surfaceMuted;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!appState.coreInfo.isAvailable || !connected)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: AppCard(
                      color: mutedSurface,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 900;
                          final actionButtons = !appState.coreInfo.isAvailable
                              ? Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: appState.importCoreFromFile,
                                      icon: const Icon(
                                        Icons.upload_file_rounded,
                                      ),
                                      label: const Text('Import core'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: appState.downloadLatestCore,
                                      icon: const Icon(
                                        Icons.cloud_download_rounded,
                                      ),
                                      label: const Text('Download stable'),
                                    ),
                                  ],
                                )
                              : FilledButton.icon(
                                  onPressed: appState.isConnected
                                      ? appState.disconnect
                                      : appState.connect,
                                  icon: Icon(
                                    appState.isConnected
                                        ? Icons.link_off
                                        : Icons.link,
                                  ),
                                  label: Text(
                                    appState.isConnected
                                        ? 'Disconnect'
                                        : 'Connect',
                                  ),
                                );

                          final details = Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appState.coreInfo.isAvailable
                                      ? 'Device not connected'
                                      : 'Core binary not found',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  appState.coreInfo.isAvailable
                                      ? 'Select a Proxmark3 port and click Connect.'
                                      : 'Import a pm3 binary or place one in assets/bundled.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.hintColor,
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppPalette.secondary.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        appState.coreInfo.isAvailable
                                            ? Icons.usb_rounded
                                            : Icons.warning_amber_rounded,
                                        color: appState.coreInfo.isAvailable
                                            ? AppPalette.secondary
                                            : AppPalette.warning,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    details,
                                  ],
                                ),
                                const SizedBox(height: 12),
                                actionButtons,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppPalette.secondary.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  appState.coreInfo.isAvailable
                                      ? Icons.usb_rounded
                                      : Icons.warning_amber_rounded,
                                  color: appState.coreInfo.isAvailable
                                      ? AppPalette.secondary
                                      : AppPalette.warning,
                                ),
                              ),
                              const SizedBox(width: 12),
                              details,
                              const SizedBox(width: 12),
                              Flexible(child: actionButtons),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                const SectionHeader(
                  title: 'Device Overview',
                  subtitle: 'Live status, quick actions, and recent activity.',
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 980;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: isWide
                              ? (constraints.maxWidth - 16) * 0.6
                              : constraints.maxWidth,
                          child: AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.usb_rounded,
                                      color: AppPalette.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        connected
                                            ? 'Proxmark3 Ready'
                                            : 'No device connected',
                                        style: theme.textTheme.titleMedium,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            (connected
                                                    ? AppPalette.success
                                                    : AppPalette.danger)
                                                .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        connected ? 'ACTIVE' : 'OFFLINE',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: connected
                                                  ? AppPalette.success
                                                  : AppPalette.danger,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  connected
                                      ? 'Iceman firmware detected. Reader modes and scripting are available.'
                                      : 'Connect your Proxmark3 to begin scanning and emulation.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.hintColor,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _statChip(
                                      context,
                                      'Core',
                                      appState.coreInfo.versionLabel ??
                                          'unknown',
                                    ),
                                    _statChip(context, 'Mode', 'Standalone'),
                                    _statChip(
                                      context,
                                      'Port',
                                      portName ?? 'Not selected',
                                    ),
                                    _statChip(context, 'Voltage', '4.98V'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: isWide
                              ? (constraints.maxWidth - 16) * 0.4
                              : constraints.maxWidth,
                          child: AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Quick Actions',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 12),
                                _actionTile(
                                  context,
                                  icon: Icons.bolt,
                                  title: 'Download Core',
                                  subtitle:
                                      'Pull latest stable core (GitHub release).',
                                  color: AppPalette.secondary,
                                  onTap: appState.isBusy
                                      ? null
                                      : appState.downloadLatestCore,
                                ),
                                const SizedBox(height: 10),
                                _actionTile(
                                  context,
                                  icon: Icons.hub,
                                  title: 'Start live console',
                                  subtitle:
                                      'Interactive pm3 session with logs.',
                                  color: AppPalette.primary,
                                  onTap: connected
                                      ? () => appState.sendCommand('hw version')
                                      : appState.connect,
                                ),
                                const SizedBox(height: 10),
                                _actionTile(
                                  context,
                                  icon: Icons.auto_fix_high,
                                  title: 'Smart scan',
                                  subtitle: 'Identify tags and run best tools.',
                                  color: AppPalette.accent,
                                  onTap: connected
                                      ? appState.startReadScan
                                      : appState.connect,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                SectionHeader(
                  title: 'Recent Activity',
                  subtitle: 'Latest operations and card interactions.',
                  trailing: TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('View logs'),
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(
                    children: [
                      _activityRow(
                        context,
                        title: 'HF card detected',
                        subtitle: 'ISO14443A • UID 04:A1:8B:29',
                        time: '2 min ago',
                      ),
                      const Divider(height: 24),
                      _activityRow(
                        context,
                        title: 'Dumped MIFARE Classic 1K',
                        subtitle: 'Keys recovered: 12/16',
                        time: '12 min ago',
                      ),
                      const Divider(height: 24),
                      _activityRow(
                        context,
                        title: 'LF T55xx emulation',
                        subtitle: 'Slot 3 • 125 kHz',
                        time: '38 min ago',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statChip(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mutedSurface = isDark
        ? const Color(0xFF15212E)
        : AppPalette.surfaceMuted;
    final outlineColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.7)
        : AppPalette.outline.withValues(alpha: 0.6);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mutedSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: outlineColor),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label ',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              TextSpan(text: value, style: theme.textTheme.labelLarge),
            ],
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 320;
              final titleWidget = Text(
                title,
                style: theme.textTheme.labelLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
              final subtitleWidget = Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
                maxLines: compact ? 3 : 2,
                overflow: TextOverflow.ellipsis,
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon, color: color),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: titleWidget),
                      ],
                    ),
                    const SizedBox(height: 8),
                    subtitleWidget,
                  ],
                );
              }

              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleWidget,
                        const SizedBox(height: 4),
                        subtitleWidget,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _activityRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String time,
  }) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        if (compact) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: AppPalette.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      time,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: AppPalette.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: Text(
                time,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
