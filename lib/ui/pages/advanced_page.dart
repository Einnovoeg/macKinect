import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../widgets/app_card.dart';
import '../widgets/section_header.dart';

enum _AdvancedGroup { hf, lf, emv, utility }

class _AdvancedVariant {
  const _AdvancedVariant({required this.label, required this.command});

  final String label;
  final String command;
}

class _AdvancedAction {
  const _AdvancedAction({
    required this.id,
    required this.label,
    required this.description,
    required this.variants,
  });

  final String id;
  final String label;
  final String description;
  final List<_AdvancedVariant> variants;
}

const Map<_AdvancedGroup, List<_AdvancedAction>> _commandLibrary = {
  _AdvancedGroup.hf: [
    _AdvancedAction(
      id: 'hfSearch',
      label: 'HF Search',
      description: 'Discover nearby high-frequency tags.',
      variants: [
        _AdvancedVariant(label: 'Standard', command: 'hf search'),
        _AdvancedVariant(label: 'Verbose', command: 'hf search -v'),
      ],
    ),
    _AdvancedAction(
      id: 'hf14aReader',
      label: 'HF 14A Reader',
      description: 'Read ISO14443-A card information.',
      variants: [
        _AdvancedVariant(label: 'Reader', command: 'hf 14a reader'),
        _AdvancedVariant(label: 'Verbose', command: 'hf 14a reader -v'),
      ],
    ),
    _AdvancedAction(
      id: 'hfMifare',
      label: 'MIFARE Check Keys',
      description: 'Check default key dictionary against MIFARE Classic.',
      variants: [
        _AdvancedVariant(label: '1K Defaults', command: 'hf mf fchk --1k'),
        _AdvancedVariant(
          label: '1K + Default Dict',
          command: 'hf mf fchk --1k -f mfc_default_keys',
        ),
      ],
    ),
    _AdvancedAction(
      id: 'hfSniff',
      label: 'HF Sniff',
      description: 'Capture HF transactions for analysis.',
      variants: [
        _AdvancedVariant(label: '14A Sniff', command: 'hf 14a sniff'),
        _AdvancedVariant(label: '14B Sniff', command: 'hf 14b sniff'),
      ],
    ),
  ],
  _AdvancedGroup.lf: [
    _AdvancedAction(
      id: 'lfSearch',
      label: 'LF Search',
      description: 'Discover nearby low-frequency tags.',
      variants: [
        _AdvancedVariant(label: 'Standard', command: 'lf search'),
        _AdvancedVariant(label: 'Verbose', command: 'lf search -v'),
      ],
    ),
    _AdvancedAction(
      id: 'lfHidReader',
      label: 'HID Reader',
      description: 'Decode HID card traffic.',
      variants: [
        _AdvancedVariant(label: 'Read', command: 'lf hid reader'),
        _AdvancedVariant(label: 'Watch', command: 'lf hid watch'),
      ],
    ),
    _AdvancedAction(
      id: 'lfT55xx',
      label: 'T55xx Toolkit',
      description: 'Detect and inspect T55xx cards.',
      variants: [
        _AdvancedVariant(label: 'Detect', command: 'lf t55xx detect'),
        _AdvancedVariant(label: 'Dump', command: 'lf t55xx dump'),
      ],
    ),
  ],
  _AdvancedGroup.emv: [
    _AdvancedAction(
      id: 'emvScan',
      label: 'EMV Scan',
      description: 'Probe EMV payment cards.',
      variants: [
        _AdvancedVariant(label: 'Scan', command: 'emv scan'),
        _AdvancedVariant(label: 'Search', command: 'emv search'),
        _AdvancedVariant(label: 'Reader', command: 'emv reader'),
      ],
    ),
    _AdvancedAction(
      id: 'emvFlow',
      label: 'EMV Transaction',
      description: 'Run standard EMV transaction helpers.',
      variants: [
        _AdvancedVariant(label: 'Execute', command: 'emv exec'),
        _AdvancedVariant(label: 'PSE', command: 'emv pse'),
        _AdvancedVariant(label: 'List Trace', command: 'emv list -1'),
      ],
    ),
  ],
  _AdvancedGroup.utility: [
    _AdvancedAction(
      id: 'deviceInfo',
      label: 'Device Info',
      description: 'Read hardware and firmware information.',
      variants: [
        _AdvancedVariant(label: 'HW Version', command: 'hw version'),
        _AdvancedVariant(label: 'HW Status', command: 'hw status'),
      ],
    ),
    _AdvancedAction(
      id: 'storageInfo',
      label: 'Storage',
      description: 'Inspect PM3 storage and memory.',
      variants: [
        _AdvancedVariant(label: 'Mem Info', command: 'mem spiffs info'),
        _AdvancedVariant(label: 'Mem Dump', command: 'mem dump'),
      ],
    ),
    _AdvancedAction(
      id: 'scripts',
      label: 'Scripts',
      description: 'Inspect and run available scripts.',
      variants: [
        _AdvancedVariant(label: 'List Scripts', command: 'script list'),
        _AdvancedVariant(
          label: 'Run Help Export',
          command: 'script run pm3_help2json.py',
        ),
      ],
    ),
  ],
};

class AdvancedPage extends StatefulWidget {
  const AdvancedPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<AdvancedPage> createState() => _AdvancedPageState();
}

class _AdvancedPageState extends State<AdvancedPage> {
  _AdvancedGroup _group = _AdvancedGroup.hf;
  late _AdvancedAction _action;
  late _AdvancedVariant _variant;

  final List<String> _queue = [];
  final TextEditingController _customCommandController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _action = _actionsFor(_group).first;
    _variant = _action.variants.first;
  }

  @override
  void dispose() {
    _customCommandController.dispose();
    super.dispose();
  }

  List<_AdvancedAction> _actionsFor(_AdvancedGroup group) =>
      _commandLibrary[group] ?? const [];

  String _groupLabel(_AdvancedGroup group) {
    return switch (group) {
      _AdvancedGroup.hf => 'HF',
      _AdvancedGroup.lf => 'LF',
      _AdvancedGroup.emv => 'EMV',
      _AdvancedGroup.utility => 'Utility',
    };
  }

  void _setGroup(_AdvancedGroup group) {
    final nextActions = _actionsFor(group);
    if (nextActions.isEmpty) return;
    setState(() {
      _group = group;
      _action = nextActions.first;
      _variant = _action.variants.first;
    });
  }

  void _setAction(String actionId) {
    final nextAction = _actionsFor(_group).firstWhere(
      (item) => item.id == actionId,
      orElse: () => _actionsFor(_group).first,
    );
    setState(() {
      _action = nextAction;
      _variant = nextAction.variants.first;
    });
  }

  void _setVariant(String label) {
    final nextVariant = _action.variants.firstWhere(
      (item) => item.label == label,
      orElse: () => _action.variants.first,
    );
    setState(() {
      _variant = nextVariant;
    });
  }

  void _addCurrentCommand() {
    setState(() {
      _queue.add(_variant.command);
    });
  }

  void _addCustomCommand() {
    final value = _customCommandController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _queue.add(value);
      _customCommandController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1080;
        final builderWidth = isWide
            ? (constraints.maxWidth - 16) * 0.56
            : constraints.maxWidth;
        final queueWidth = isWide
            ? (constraints.maxWidth - 16) * 0.44
            : constraints.maxWidth;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Advanced',
                subtitle:
                    'Build command chains with contextual presets and run them against the connected PM3.',
                trailing: Tooltip(
                  message: 'Open full Proxmark3 documentation.',
                  child: TextButton.icon(
                    onPressed: appState.openDocumentation,
                    icon: const Icon(Icons.menu_book_rounded),
                    label: const Text('Documentation'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: builderWidth,
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Command Builder',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(
                                width: 160,
                                child: DropdownButtonFormField<_AdvancedGroup>(
                                  initialValue: _group,
                                  decoration: const InputDecoration(
                                    labelText: 'Group',
                                  ),
                                  items: _AdvancedGroup.values
                                      .map(
                                        (group) => DropdownMenuItem(
                                          value: group,
                                          child: Text(_groupLabel(group)),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (group) {
                                    if (group != null) {
                                      _setGroup(group);
                                    }
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 240,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _action.id,
                                  decoration: const InputDecoration(
                                    labelText: 'Action',
                                  ),
                                  items: _actionsFor(_group)
                                      .map(
                                        (action) => DropdownMenuItem(
                                          value: action.id,
                                          child: Text(action.label),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      _setAction(value);
                                    }
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 230,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _variant.label,
                                  decoration: const InputDecoration(
                                    labelText: 'Preset',
                                  ),
                                  items: _action.variants
                                      .map(
                                        (variant) => DropdownMenuItem(
                                          value: variant.label,
                                          child: Text(variant.label),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      _setVariant(value);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _action.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.35),
                              border: Border.all(
                                color: theme.colorScheme.outline.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                            child: SelectableText(
                              _variant.command,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontFamily: 'Menlo',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              Tooltip(
                                message:
                                    'Queue this command for batch execution.',
                                child: FilledButton.icon(
                                  onPressed: _addCurrentCommand,
                                  icon: const Icon(Icons.playlist_add_rounded),
                                  label: const Text('Add to chain'),
                                ),
                              ),
                              Tooltip(
                                message:
                                    'Run the selected command immediately.',
                                child: OutlinedButton.icon(
                                  onPressed: appState.isConnected
                                      ? () => appState.sendCommand(
                                          _variant.command,
                                        )
                                      : null,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Run now'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Custom command',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 420;
                              if (compact) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextField(
                                      controller: _customCommandController,
                                      decoration: const InputDecoration(
                                        hintText: 'ex: hf mf autopwn',
                                      ),
                                      onSubmitted: (_) => _addCustomCommand(),
                                    ),
                                    const SizedBox(height: 10),
                                    FilledButton.tonalIcon(
                                      onPressed: _addCustomCommand,
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('Add'),
                                    ),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _customCommandController,
                                      decoration: const InputDecoration(
                                        hintText: 'ex: hf mf autopwn',
                                      ),
                                      onSubmitted: (_) => _addCustomCommand(),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton.tonalIcon(
                                    onPressed: _addCustomCommand,
                                    icon: const Icon(Icons.add_rounded),
                                    label: const Text('Add'),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: queueWidth,
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.queue_play_next_rounded,
                                color: AppPalette.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Command Chain',
                                style: theme.textTheme.titleMedium,
                              ),
                              const Spacer(),
                              Text(
                                '${_queue.length} queued',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_queue.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.28),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'No queued commands yet. Add from presets or custom input.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.hintColor,
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemBuilder: (context, index) {
                                final command = _queue[index];
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    radius: 13,
                                    backgroundColor: AppPalette.primary
                                        .withValues(alpha: 0.15),
                                    child: Text(
                                      '${index + 1}',
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ),
                                  title: Text(
                                    command,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontFamily: 'Menlo',
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Remove command',
                                    onPressed: () {
                                      setState(() {
                                        _queue.removeAt(index);
                                      });
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                );
                              },
                              separatorBuilder: (context, _) =>
                                  const Divider(height: 1),
                              itemCount: _queue.length,
                            ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                onPressed:
                                    _queue.isEmpty || !appState.isConnected
                                    ? null
                                    : () => appState.runCommandChain(_queue),
                                icon: const Icon(Icons.play_circle_rounded),
                                label: const Text('Run chain'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _queue.isEmpty
                                    ? null
                                    : () {
                                        setState(() {
                                          _queue.clear();
                                        });
                                      },
                                icon: const Icon(Icons.clear_all_rounded),
                                label: const Text('Clear'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Commands run sequentially with a short delay between each step.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
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
}
