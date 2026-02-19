import 'package:flutter/material.dart';

import 'app/app.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.initialize();
  runApp(MacKinectApp(state: appState));
}
