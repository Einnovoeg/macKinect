import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/palette.dart';

class StatusFooter extends StatefulWidget {
  const StatusFooter({
    super.key,
    required this.coreVersion,
    required this.channelLabel,
    required this.appVersion,
  });

  final String coreVersion;
  final String channelLabel;
  final String appVersion;

  @override
  State<StatusFooter> createState() => _StatusFooterState();
}

class _StatusFooterState extends State<StatusFooter> {
  late Timer _timer;
  String _timestamp = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _timestamp = DateFormat('EEE, MMM d • h:mm:ss a').format(now);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outline.withValues(alpha: 0.75)
              : AppPalette.outline.withValues(alpha: 0.6),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.memory_rounded, color: AppPalette.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.coreVersion,
                        style: theme.textTheme.labelLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        widget.channelLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _timestamp,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.hintColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'v${widget.appVersion}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Icon(Icons.memory_rounded, color: AppPalette.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.coreVersion,
                  style: theme.textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.channelLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.primary,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                _timestamp,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'v${widget.appVersion}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
