import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'pages/advanced_page.dart';
import 'pages/home_page.dart';
import 'pages/read_cards_page.dart';
import 'pages/saved_cards_page.dart';
import 'pages/settings_page.dart';
import 'pages/slot_manager_page.dart';
import 'pages/tools_page.dart';
import 'pages/write_cards_page.dart';
import 'widgets/sidebar.dart';
import 'widgets/status_footer.dart';
import 'widgets/top_bar.dart';
import 'widgets/onboarding_overlay.dart';

enum _CoreMenuAction {
  updateCurrent,
  downloadStable,
  downloadExperimental,
  addSeparate,
  installLocal,
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  final List<NavItem> _items = const [
    NavItem(label: 'Home', icon: Icons.dashboard_rounded),
    NavItem(label: 'Slots', icon: Icons.view_module_rounded),
    NavItem(label: 'Saved Cards', icon: Icons.bookmark_rounded),
    NavItem(label: 'Read', icon: Icons.radar_rounded),
    NavItem(label: 'Advanced', icon: Icons.code_rounded),
    NavItem(label: 'Write', icon: Icons.edit_rounded),
    NavItem(label: 'Tools', icon: Icons.build_rounded),
    NavItem(label: 'Settings', icon: Icons.settings_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coreLabel = appState.coreInfo.versionLabel ?? 'unknown core';
    final portLabel =
        appState.selectedPort?.displayName ?? 'No device selected';
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [
                    Color(0xFF0B121A),
                    Color(0xFF0F1823),
                    Color(0xFF121F2D),
                  ]
                : const [
                    Color(0xFFF5F7FA),
                    Color(0xFFF2F4F8),
                    Color(0xFFEFF2F6),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            const _AmbientBlob(
              color: Color(0xFF66E3BA),
              alignment: Alignment(-0.9, -0.6),
              size: 320,
            ),
            const _AmbientBlob(
              color: Color(0xFF7EA6FF),
              alignment: Alignment(0.8, -0.5),
              size: 280,
            ),
            const _AmbientBlob(
              color: Color(0xFFFFB38A),
              alignment: Alignment(0.6, 0.9),
              size: 340,
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compactSidebar = constraints.maxWidth < 1220;
                  final contentPadding = constraints.maxWidth < 900
                      ? 12.0
                      : 20.0;
                  return Row(
                    children: [
                      Sidebar(
                        items: _items,
                        selectedIndex: _selectedIndex,
                        compact: compactSidebar,
                        onSelect: (index) =>
                            setState(() => _selectedIndex = index),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(contentPadding),
                          child: Column(
                            children: [
                              TopBar(
                                title: _items[_selectedIndex].label,
                                connected: appState.isConnected,
                                deviceLabel: appState.isConnected
                                    ? 'Proxmark3 • $portLabel'
                                    : portLabel,
                                ports: appState.ports,
                                selectedPort: appState.selectedPort,
                                onSelectPort: appState.selectPort,
                                busy: appState.isBusy,
                                onToggleConnection: () {
                                  if (appState.isConnected) {
                                    appState.disconnect();
                                  } else {
                                    appState.connect();
                                  }
                                },
                                actions: [
                                  Tooltip(
                                    message:
                                        'Refresh available serial ports and auto-select Iceman when present.',
                                    child: OutlinedButton.icon(
                                      onPressed: appState.refreshPorts,
                                      icon: const Icon(Icons.tune_rounded),
                                      label: const Text('Refresh Ports'),
                                    ),
                                  ),
                                  Tooltip(
                                    message:
                                        'Download the latest stable core from GitHub sources configured in Settings.',
                                    child: FilledButton.tonalIcon(
                                      onPressed: appState.isBusy
                                          ? null
                                          : appState.downloadLatestCore,
                                      icon: const Icon(
                                        Icons.cloud_download_rounded,
                                      ),
                                      label: const Text('Download Core'),
                                    ),
                                  ),
                                  Tooltip(
                                    message:
                                        'Download, update, or import Proxmark3 core binaries.',
                                    child: PopupMenuButton<_CoreMenuAction>(
                                      enabled: !appState.isBusy,
                                      onSelected: (action) =>
                                          _handleCoreAction(appState, action),
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: _CoreMenuAction.updateCurrent,
                                          child: Text('Update Current Core'),
                                        ),
                                        PopupMenuItem(
                                          value: _CoreMenuAction.downloadStable,
                                          child: Text('Download Latest Stable'),
                                        ),
                                        PopupMenuItem(
                                          value: _CoreMenuAction
                                              .downloadExperimental,
                                          child: Text(
                                            'Download Experimental/Beta',
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: _CoreMenuAction.addSeparate,
                                          child: Text('Add Separate Core'),
                                        ),
                                        PopupMenuItem(
                                          value: _CoreMenuAction.installLocal,
                                          child: Text('Install Local Core'),
                                        ),
                                      ],
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline
                                                .withValues(alpha: 0.45),
                                          ),
                                        ),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 9,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.memory_rounded,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text('Core Options'),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Tooltip(
                                    message:
                                        'Open full Proxmark3 documentation wiki.',
                                    child: OutlinedButton.icon(
                                      onPressed: appState.openDocumentation,
                                      icon: const Icon(Icons.menu_book_rounded),
                                      label: const Text('Docs'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: _pageForIndex(
                                    _selectedIndex,
                                    appState,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              StatusFooter(
                                coreVersion: 'Core • $coreLabel',
                                channelLabel: 'Stable Channel',
                                appVersion: '0.1.0',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (appState.showOnboarding) OnboardingOverlay(appState: appState),
          ],
        ),
      ),
    );
  }

  Widget _pageForIndex(int index, AppState appState) {
    switch (index) {
      case 0:
        return HomePage(
          key: ValueKey(index),
          connected: appState.isConnected,
          portName: appState.selectedPort?.displayName,
        );
      case 1:
        return const SlotManagerPage(key: ValueKey('slots'));
      case 2:
        return const SavedCardsPage(key: ValueKey('saved'));
      case 3:
        return ReadCardsPage(key: const ValueKey('read'), appState: appState);
      case 4:
        return AdvancedPage(
          key: const ValueKey('advanced'),
          appState: appState,
        );
      case 5:
        return const WriteCardsPage(key: ValueKey('write'));
      case 6:
        return ToolsPage(key: const ValueKey('tools'), appState: appState);
      case 7:
        return SettingsPage(
          key: const ValueKey('settings'),
          appState: appState,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _handleCoreAction(
    AppState appState,
    _CoreMenuAction action,
  ) async {
    switch (action) {
      case _CoreMenuAction.updateCurrent:
      case _CoreMenuAction.downloadStable:
        await appState.downloadLatestCore();
        break;
      case _CoreMenuAction.downloadExperimental:
        await appState.downloadExperimentalCore();
        break;
      case _CoreMenuAction.addSeparate:
        await appState.addSeparateCoreFromFile();
        break;
      case _CoreMenuAction.installLocal:
        await appState.importCoreFromFile();
        break;
    }
  }
}

class _AmbientBlob extends StatelessWidget {
  const _AmbientBlob({
    required this.color,
    required this.alignment,
    required this.size,
  });

  final Color color;
  final Alignment alignment;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.35),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}
