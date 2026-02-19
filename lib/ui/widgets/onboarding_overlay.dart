import 'dart:ui';

import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/palette.dart';
import 'app_card.dart';

class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({super.key, required this.appState});

  final AppState appState;

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  int _stepIndex = 0;
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps(context);
    final step = steps[_stepIndex];

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: AppCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: step.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(step.icon, color: step.accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                step.subtitle,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context).hintColor,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => widget.appState.closeOnboarding(
                            dismissPermanently: _dontShowAgain,
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ...step.body,
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Checkbox(
                          value: _dontShowAgain,
                          onChanged: (value) {
                            setState(() => _dontShowAgain = value ?? false);
                          },
                        ),
                        const Text('Don\'t show again'),
                        const Spacer(),
                        TextButton(
                          onPressed: _stepIndex == 0
                              ? null
                              : () => setState(() => _stepIndex -= 1),
                          child: const Text('Back'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            if (_stepIndex < steps.length - 1) {
                              setState(() => _stepIndex += 1);
                            } else {
                              widget.appState.closeOnboarding(
                                dismissPermanently: _dontShowAgain,
                              );
                            }
                          },
                          child: Text(
                            _stepIndex < steps.length - 1 ? 'Next' : 'Finish',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_OnboardingStep> _buildSteps(BuildContext context) {
    final theme = Theme.of(context);
    final appState = widget.appState;

    return [
      _OnboardingStep(
        title: 'Add the Proxmark core',
        subtitle: 'Import a pm3 binary or download the latest stable build.',
        icon: Icons.memory_rounded,
        accent: AppPalette.secondary,
        body: [
          Text(
            'macKinect needs the pm3 client binary from Iceman. You can import it from a local build or download a stable core.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: appState.isBusy ? null : appState.importCoreFromFile,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Import core'),
              ),
              OutlinedButton.icon(
                onPressed: appState.isBusy ? null : appState.downloadLatestCore,
                icon: const Icon(Icons.cloud_download_rounded),
                label: const Text('Download stable'),
              ),
            ],
          ),
          if (appState.statusMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                appState.statusMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.danger,
                ),
              ),
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
        ],
      ),
      _OnboardingStep(
        title: 'Select your device port',
        subtitle: 'Choose the Proxmark3 USB port from the dropdown.',
        icon: Icons.usb_rounded,
        accent: AppPalette.primary,
        body: [
          Text(
            'Look for ports like /dev/tty.usbmodem* on macOS. If nothing shows, refresh the port list.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (appState.ports.isEmpty)
            Text(
              'No ports detected yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.danger,
              ),
            )
          else
            DropdownButtonFormField(
              initialValue: appState.selectedPort,
              items: appState.ports
                  .map(
                    (port) => DropdownMenuItem(
                      value: port,
                      child: Text(
                        port.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: appState.selectPort,
              decoration: const InputDecoration(
                labelText: 'Device port',
                prefixIcon: Icon(Icons.usb_rounded),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: appState.isBusy ? null : appState.refreshPorts,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh ports'),
          ),
        ],
      ),
      _OnboardingStep(
        title: 'Connect to Proxmark3',
        subtitle: 'Start a live pm3 session.',
        icon: Icons.link_rounded,
        accent: AppPalette.success,
        body: [
          Text(
            'Hit Connect in the top bar. Once connected you will see live output in Tools.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: appState.isBusy
                ? null
                : (appState.isConnected
                      ? appState.disconnect
                      : appState.connect),
            icon: Icon(appState.isConnected ? Icons.link_off : Icons.link),
            label: Text(appState.isConnected ? 'Disconnect' : 'Connect'),
          ),
        ],
      ),
      _OnboardingStep(
        title: 'Run your first command',
        subtitle: 'Verify that everything is live.',
        icon: Icons.terminal_rounded,
        accent: AppPalette.accent,
        body: [
          Text(
            'Try a quick command like hw version or hf search. The console will show live output.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            children: [
              FilledButton.icon(
                onPressed: appState.isConnected
                    ? () => appState.sendCommand('hw version')
                    : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Run hw version'),
              ),
              OutlinedButton.icon(
                onPressed: appState.isConnected
                    ? () => appState.sendCommand('hf search')
                    : null,
                icon: const Icon(Icons.radar_rounded),
                label: const Text('Run hf search'),
              ),
            ],
          ),
        ],
      ),
    ];
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.body,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<Widget> body;
}
