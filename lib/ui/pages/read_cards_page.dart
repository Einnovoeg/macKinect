import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../widgets/app_card.dart';
import '../widgets/section_header.dart';

class ReadCardsPage extends StatelessWidget {
  const ReadCardsPage({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mutedSurface = isDark
        ? const Color(0xFF15212E)
        : AppPalette.surfaceMuted;
    final outlineColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.7)
        : AppPalette.outline.withValues(alpha: 0.5);
    final scanGradientEnd = isDark
        ? theme.colorScheme.surface
        : AppPalette.surface;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 980;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Read Cards',
                subtitle: 'Detect, parse, and save tag data in real-time.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: isWide
                        ? (constraints.maxWidth - 16) * 0.62
                        : constraints.maxWidth,
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 720;
                              final actions = Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Tooltip(
                                    message:
                                        'Run a high-frequency search (13.56 MHz).',
                                    child: FilledButton.icon(
                                      onPressed: appState.isConnected
                                          ? appState.startHfScan
                                          : null,
                                      icon: const Icon(Icons.radar_rounded),
                                      label: const Text('Scan HF'),
                                    ),
                                  ),
                                  Tooltip(
                                    message:
                                        'Run a low-frequency search (125/134 kHz).',
                                    child: OutlinedButton.icon(
                                      onPressed: appState.isConnected
                                          ? appState.startLfScan
                                          : null,
                                      icon: const Icon(
                                        Icons.graphic_eq_rounded,
                                      ),
                                      label: const Text('Scan LF'),
                                    ),
                                  ),
                                  Tooltip(
                                    message:
                                        'Run an EMV-oriented high-frequency scan.',
                                    child: FilledButton.tonalIcon(
                                      onPressed: appState.isConnected
                                          ? appState.startEmvScan
                                          : null,
                                      icon: const Icon(
                                        Icons.credit_card_rounded,
                                      ),
                                      label: const Text('Scan EMV'),
                                    ),
                                  ),
                                  Tooltip(
                                    message:
                                        'Continuously repeat HF search until stopped.',
                                    child: FilledButton.tonalIcon(
                                      onPressed: appState.isConnected
                                          ? appState.startContinuousHfScan
                                          : null,
                                      icon: const Icon(Icons.loop_rounded),
                                      label: const Text('Continuous HF'),
                                    ),
                                  ),
                                  Tooltip(
                                    message:
                                        'Continuously repeat LF search until stopped.',
                                    child: OutlinedButton.icon(
                                      onPressed: appState.isConnected
                                          ? appState.startContinuousLfScan
                                          : null,
                                      icon: const Icon(Icons.sync_rounded),
                                      label: const Text('Continuous LF'),
                                    ),
                                  ),
                                  if (appState.scanInProgress ||
                                      appState.isContinuousScan)
                                    Tooltip(
                                      message:
                                          'Stop the active scan loop immediately.',
                                      child: FilledButton.icon(
                                        onPressed: appState.stopReadScan,
                                        icon: const Icon(Icons.stop_rounded),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppPalette.danger,
                                          foregroundColor: Colors.white,
                                        ),
                                        label: const Text('Stop Scan'),
                                      ),
                                    ),
                                ],
                              );

                              if (compact) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.radar_rounded,
                                          color: AppPalette.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Live scan',
                                            style: theme.textTheme.titleMedium,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    actions,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Icon(
                                    Icons.radar_rounded,
                                    color: AppPalette.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Live scan',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const Spacer(),
                                  actions,
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 240,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: outlineColor),
                              gradient: LinearGradient(
                                colors: [
                                  AppPalette.primary.withValues(alpha: 0.1),
                                  AppPalette.secondary.withValues(alpha: 0.08),
                                  scanGradientEnd,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    appState.scanInProgress
                                        ? Icons.radar_rounded
                                        : Icons.contactless_rounded,
                                    size: 64,
                                    color: AppPalette.secondary,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    (appState.scanInProgress ||
                                            appState.isContinuousScan)
                                        ? appState.scanModeLabel.isEmpty
                                              ? 'Scanning...'
                                              : '${appState.scanModeLabel}...'
                                        : appState.isConnected
                                        ? 'Tap a tag to read'
                                        : 'Connect device to read',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    appState.isContinuousScan
                                        ? 'Continuous mode active • press Stop to end'
                                        : appState.scanInProgress
                                        ? 'Listening for card responses'
                                        : 'Auto-detect enabled • HF + LF + EMV',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.hintColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Recent reads',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: appState.recentReadUids.isEmpty
                                ? [
                                    Chip(
                                      label: const Text('No reads yet'),
                                      avatar: const Icon(
                                        Icons.nfc_rounded,
                                        size: 18,
                                      ),
                                      backgroundColor: mutedSurface,
                                      side: BorderSide(color: outlineColor),
                                    ),
                                  ]
                                : appState.recentReadUids
                                      .map(
                                        (uid) => Chip(
                                          label: Text('UID $uid'),
                                          avatar: const Icon(
                                            Icons.nfc_rounded,
                                            size: 18,
                                          ),
                                          backgroundColor: mutedSurface,
                                          side: BorderSide(color: outlineColor),
                                        ),
                                      )
                                      .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: isWide
                        ? (constraints.maxWidth - 16) * 0.38
                        : constraints.maxWidth,
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Decoded data',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _dataRow(
                            context,
                            'Type',
                            appState.lastReadType ?? '--',
                          ),
                          _dataRow(
                            context,
                            'UID',
                            appState.lastReadUid ?? '--',
                          ),
                          _dataRow(
                            context,
                            'SAK',
                            appState.lastReadSak ?? '--',
                          ),
                          _dataRow(
                            context,
                            'ATQA',
                            appState.lastReadAtqa ?? '--',
                          ),
                          const Divider(height: 24),
                          Text('Actions', style: theme.textTheme.labelLarge),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.save_rounded),
                            label: const Text('Save to library'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Clone to slot'),
                          ),
                          if (appState.statusMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                appState.statusMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.hintColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dataRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.labelLarge,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
