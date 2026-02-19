import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/serial_port_info.dart';
import '../../theme/palette.dart';
import 'status_pill.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.title,
    required this.connected,
    required this.deviceLabel,
    required this.onToggleConnection,
    required this.ports,
    required this.selectedPort,
    required this.onSelectPort,
    required this.busy,
    this.actions = const [],
  });

  final String title;
  final bool connected;
  final String deviceLabel;
  final VoidCallback onToggleConnection;
  final List<SerialPortInfo> ports;
  final SerialPortInfo? selectedPort;
  final ValueChanged<SerialPortInfo?> onSelectPort;
  final bool busy;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: (isDark ? theme.colorScheme.surface : AppPalette.surface)
                .withValues(alpha: isDark ? 0.92 : 0.82),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? theme.colorScheme.outline.withValues(alpha: 0.75)
                  : AppPalette.outline.withValues(alpha: 0.7),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 980;
              final availableWidth = math.max(0.0, constraints.maxWidth - 24);
              final dropdownMaxWidth = isCompact
                  ? availableWidth
                  : math.min(280.0, availableWidth);
              final statusRow = Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusPill(
                    label: connected ? 'Connected' : 'Disconnected',
                    color: connected ? AppPalette.success : AppPalette.danger,
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isCompact ? constraints.maxWidth - 24 : 300,
                    ),
                    child: Text(
                      deviceLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.hintColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _PortDropdown(
                    ports: ports,
                    selectedPort: selectedPort,
                    onSelect: onSelectPort,
                    maxWidth: dropdownMaxWidth,
                  ),
                ],
              );

              final actionRow = Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ...actions,
                  Tooltip(
                    message: connected
                        ? 'Close current PM3 session.'
                        : 'Start PM3 session on selected serial port.',
                    child: FilledButton.icon(
                      onPressed: busy ? null : onToggleConnection,
                      style: FilledButton.styleFrom(
                        backgroundColor: connected
                            ? AppPalette.danger.withValues(alpha: 0.9)
                            : AppPalette.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: Icon(connected ? Icons.link_off : Icons.link),
                      label: Text(
                        busy
                            ? 'Working'
                            : connected
                            ? 'Disconnect'
                            : 'Connect',
                      ),
                    ),
                  ),
                ],
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    statusRow,
                    const SizedBox(height: 12),
                    actionRow,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        statusRow,
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(child: actionRow),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PortDropdown extends StatelessWidget {
  const _PortDropdown({
    required this.ports,
    required this.selectedPort,
    required this.onSelect,
    required this.maxWidth,
  });

  final List<SerialPortInfo> ports;
  final SerialPortInfo? selectedPort;
  final ValueChanged<SerialPortInfo?> onSelect;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2633) : AppPalette.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outline.withValues(alpha: 0.7)
              : AppPalette.outline.withValues(alpha: 0.6),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DropdownButtonHideUnderline(
          child: Tooltip(
            message: 'Select the Proxmark serial port.',
            child: DropdownButton<SerialPortInfo>(
              isDense: true,
              isExpanded: true,
              value: ports.contains(selectedPort) ? selectedPort : null,
              hint: Text(ports.isEmpty ? 'No ports' : 'Select port'),
              selectedItemBuilder: (context) => ports
                  .map(
                    (port) => Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        port.name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  )
                  .toList(),
              items: ports
                  .map(
                    (port) => DropdownMenuItem(
                      value: port,
                      child: Text(
                        port.name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onSelect,
            ),
          ),
        ),
      ),
    );
  }
}
