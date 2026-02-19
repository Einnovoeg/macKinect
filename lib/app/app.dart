import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../ui/app_shell.dart';

class MacKinectApp extends StatelessWidget {
  const MacKinectApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: Consumer<AppState>(
        builder: (context, appState, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'macKinect',
          theme: AppTheme.light(palette: appState.accentPalette),
          darkTheme: AppTheme.dark(palette: appState.accentPalette),
          themeMode: appState.themeMode,
          home: const AppShell(),
        ),
      ),
    );
  }
}
