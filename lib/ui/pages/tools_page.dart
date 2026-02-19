import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../widgets/app_card.dart';
import '../widgets/section_header.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 980;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Tools & Console',
                subtitle: 'Advanced workflows and live command sessions.',
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
                    child: Column(
                      children: [
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    color: AppPalette.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'HF Toolkit',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _toolRow('MIFARE Classic', 'Key recovery + dump'),
                              _toolRow('DESFire', 'ATS parsing, file browsing'),
                              _toolRow('NTAG', 'NDEF quick view'),
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
                                  Icon(
                                    Icons.graphic_eq_rounded,
                                    color: AppPalette.secondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'LF Toolkit',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _toolRow('T55xx', 'Detect, read, write, clone'),
                              _toolRow('HID Prox', 'Decode + emulate'),
                              _toolRow('EM410x', 'Dump + replay'),
                            ],
                          ),
                        ),
                      ],
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
                                Icons.terminal_rounded,
                                color: AppPalette.accent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Live Console',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              OutlinedButton.icon(
                                onPressed:
                                    widget.appState.consoleEntries.isNotEmpty
                                    ? widget.appState.clearConsole
                                    : null,
                                icon: const Icon(Icons.delete_sweep_rounded),
                                label: const Text('Clear'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 280,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppPalette.inkSoft,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListView(
                              children:
                                  widget.appState.consoleEntries.isNotEmpty
                                  ? widget.appState.consoleEntries
                                        .map(
                                          (entry) => _ConsoleLine(
                                            text: entry.message,
                                            isError: entry.isError,
                                          ),
                                        )
                                        .toList()
                                  : [
                                      const _ConsoleLine(
                                        text:
                                            'No session yet. Connect a device to start.',
                                      ),
                                    ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _controller,
                            onSubmitted: (value) {
                              widget.appState.sendCommand(value);
                              _controller.clear();
                            },
                            decoration: const InputDecoration(
                              hintText: 'Enter pm3 command (ex: hf mf dump)',
                              prefixIcon: Icon(Icons.chevron_right_rounded),
                            ),
                          ),
                          if (widget.appState.statusMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                widget.appState.statusMessage!,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: AppPalette.danger),
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

  Widget _toolRow(String title, String subtitle) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: AppPalette.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
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
}

class _ConsoleLine extends StatelessWidget {
  const _ConsoleLine({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: isError ? Colors.redAccent.shade100 : Colors.white70,
          fontFamily: 'Menlo',
          fontSize: 12,
        ),
      ),
    );
  }
}
