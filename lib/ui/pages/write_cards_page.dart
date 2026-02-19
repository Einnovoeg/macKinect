import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../widgets/app_card.dart';
import '../widgets/section_header.dart';

class WriteCardsPage extends StatelessWidget {
  const WriteCardsPage({super.key});

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 980;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Write Cards',
                subtitle: 'Program tags from your library or new templates.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: isWide
                        ? (constraints.maxWidth - 16) * 0.45
                        : constraints.maxWidth,
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select source',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _sourceTile(
                            context,
                            'Library card',
                            'Campus Badge 3',
                            true,
                          ),
                          const SizedBox(height: 10),
                          _sourceTile(
                            context,
                            'Template',
                            'MIFARE Classic 1K',
                            false,
                          ),
                          const SizedBox(height: 10),
                          _sourceTile(
                            context,
                            'Custom dump',
                            'Import a .bin file',
                            false,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Write options',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          _toggle(context, 'Verify after write', true),
                          _toggle(context, 'Lock blocks when supported', false),
                          _toggle(context, 'Auto-assign slot', true),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: isWide
                        ? (constraints.maxWidth - 16) * 0.55
                        : constraints.maxWidth,
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.edit_rounded,
                                color: AppPalette.accent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Write station',
                                style: theme.textTheme.titleMedium,
                              ),
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.flash_on_rounded),
                                label: const Text('Write now'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 220,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: outlineColor),
                              color: mutedSurface,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.contactless_rounded,
                                    size: 56,
                                    color: AppPalette.accent,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Place target tag on antenna',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Waiting for tag...',
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
                            'Safety checks',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _pill('Battery OK', AppPalette.success),
                              _pill('Key verified', AppPalette.success),
                              _pill('UID writable', AppPalette.warning),
                            ],
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

  Widget _sourceTile(
    BuildContext context,
    String title,
    String subtitle,
    bool selected,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mutedSurface = isDark
        ? const Color(0xFF15212E)
        : AppPalette.surfaceMuted;
    final outlineColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.7)
        : AppPalette.outline.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected
            ? AppPalette.primary.withValues(alpha: 0.12)
            : mutedSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? AppPalette.primary.withValues(alpha: 0.4)
              : outlineColor,
        ),
      ),
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: selected ? AppPalette.primary : theme.hintColor,
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
        ],
      ),
    );
  }

  Widget _toggle(BuildContext context, String label, bool value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Switch(value: value, onChanged: (_) {}),
          const SizedBox(width: 8),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
