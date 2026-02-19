import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/console_entry.dart';
import '../models/core_info.dart';
import '../models/serial_port_info.dart';
import '../models/update_info.dart';
import '../services/core_manager.dart';
import '../services/pm3_service.dart';
import '../services/serial_port_service.dart';
import '../services/update_service.dart';
import '../theme/palette.dart';

enum ReadScanMode {
  none,
  hfSingle,
  lfSingle,
  emvSingle,
  hfContinuous,
  lfContinuous,
}

class AppState extends ChangeNotifier {
  AppState({
    CoreManager? coreManager,
    SerialPortService? serialPortService,
    Pm3Service? pm3Service,
    UpdateService? updateService,
  }) : _coreManager = coreManager ?? CoreManager(),
       _serialPortService = serialPortService ?? SerialPortService(),
       _pm3Service = pm3Service ?? Pm3Service(),
       _updateService = updateService ?? UpdateService();

  final CoreManager _coreManager;
  final SerialPortService _serialPortService;
  final Pm3Service _pm3Service;
  final UpdateService _updateService;

  CoreInfo _coreInfo = const CoreInfo(path: null, source: CoreSource.missing);
  List<SerialPortInfo> _ports = const [];
  SerialPortInfo? _selectedPort;
  bool _connected = false;
  bool _busy = false;
  String? _statusMessage;
  UpdateInfo? _latestUpdate;
  final List<ConsoleEntry> _console = [];
  StreamSubscription<ConsoleEntry>? _consoleSub;
  bool _showOnboarding = false;
  bool _onboardingDismissed = false;
  ThemeMode _themeMode = ThemeMode.system;
  double? _downloadProgress;
  int _downloadReceived = 0;
  int _downloadTotal = 0;
  DateTime? _downloadStart;
  double? _downloadSpeed;
  bool _scanInProgress = false;
  ReadScanMode _scanMode = ReadScanMode.none;
  Timer? _continuousScanTimer;
  DateTime? _lastScanStartedAt;
  String? _lastReadType;
  String? _lastReadUid;
  String? _lastReadSak;
  String? _lastReadAtqa;
  final List<String> _recentReadUids = [];
  bool _disposed = false;
  AccentPalette _accentPalette = AccentPalette.blue;

  CoreInfo get coreInfo => _coreInfo;
  List<SerialPortInfo> get ports => _ports;
  SerialPortInfo? get selectedPort => _selectedPort;
  bool get isConnected => _connected;
  bool get isBusy => _busy;
  String? get statusMessage => _statusMessage;
  UpdateInfo? get latestUpdate => _latestUpdate;
  List<ConsoleEntry> get consoleEntries => List.unmodifiable(_console);
  bool get showOnboarding => _showOnboarding;
  ThemeMode get themeMode => _themeMode;
  bool get scanInProgress => _scanInProgress;
  bool get isContinuousScan => _isContinuousMode(_scanMode);
  AccentPalette get accentPalette => _accentPalette;
  String get scanModeLabel {
    switch (_scanMode) {
      case ReadScanMode.hfSingle:
        return 'HF scan';
      case ReadScanMode.lfSingle:
        return 'LF scan';
      case ReadScanMode.emvSingle:
        return 'EMV scan';
      case ReadScanMode.hfContinuous:
        return 'Continuous HF scan';
      case ReadScanMode.lfContinuous:
        return 'Continuous LF scan';
      case ReadScanMode.none:
        return '';
    }
  }

  String? get lastReadType => _lastReadType;
  String? get lastReadUid => _lastReadUid;
  String? get lastReadSak => _lastReadSak;
  String? get lastReadAtqa => _lastReadAtqa;
  List<String> get recentReadUids => List.unmodifiable(_recentReadUids);
  double? get downloadProgress => _downloadProgress;
  String? get downloadProgressText {
    if (_downloadReceived == 0 && _downloadTotal == 0) return null;
    if (_downloadTotal > 0) {
      final pct = (_downloadProgress ?? 0) * 100;
      final speed = _downloadSpeed != null
          ? ' • ${_formatBytes(_downloadSpeed!.round())}/s'
          : '';
      return '${_formatBytes(_downloadReceived)} / ${_formatBytes(_downloadTotal)} (${pct.toStringAsFixed(0)}%)$speed';
    }
    final speed = _downloadSpeed != null
        ? ' • ${_formatBytes(_downloadSpeed!.round())}/s'
        : '';
    return '${_formatBytes(_downloadReceived)} downloaded$speed';
  }

  Future<void> initialize() async {
    await _loadSettings();
    AppPalette.applyPalette(_accentPalette);
    _showOnboarding = false;
    await refreshPorts();
    await refreshCore();
    if (!_coreInfo.isAvailable) {
      await _autoDownloadCore();
    }
    _consoleSub = _pm3Service.output.listen((entry) {
      if (_disposed) return;
      _console.add(entry);
      _handleOutput(entry);
      if (_console.length > 250) {
        _console.removeRange(0, _console.length - 250);
      }
      notifyListeners();
    });
  }

  Future<void> refreshPorts() async {
    final previousName = _selectedPort?.name;
    _ports = _serialPortService.listPorts();
    if (_ports.isEmpty) {
      _selectedPort = null;
      if (!_connected) {
        _statusMessage =
            'No serial ports detected. Check USB connection and permissions.';
      }
    } else {
      final preferred = _findPreferredPort(_ports);
      if (preferred != null) {
        _selectedPort = preferred;
      } else {
        SerialPortInfo? previousPort;
        if (previousName != null) {
          for (final port in _ports) {
            if (port.name == previousName) {
              previousPort = port;
              break;
            }
          }
        }
        _selectedPort = previousPort ?? _ports.first;
      }
      if (_statusMessage != null &&
          _statusMessage!.toLowerCase().contains('no serial ports')) {
        _statusMessage = null;
      }
    }
    notifyListeners();
  }

  Future<void> closeOnboarding({bool dismissPermanently = false}) async {
    _showOnboarding = false;
    if (dismissPermanently) {
      _onboardingDismissed = true;
      await _saveSettings();
    }
    notifyListeners();
  }

  void reopenOnboarding() {
    _showOnboarding = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setAccentPalette(AccentPalette palette) async {
    if (_accentPalette == palette) return;
    _accentPalette = palette;
    AppPalette.applyPalette(_accentPalette);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> refreshCore() async {
    _coreInfo = await _coreManager.resolveCore();
    notifyListeners();
  }

  void selectPort(SerialPortInfo? port) {
    _selectedPort = port;
    notifyListeners();
  }

  Future<void> connect() async {
    if (_connected || _busy) return;
    _busy = true;
    _statusMessage = null;
    notifyListeners();

    if (_coreInfo.path == null) {
      _statusMessage =
          'No Proxmark3 core found. Add a bundled build or install pm3.';
      _busy = false;
      notifyListeners();
      return;
    }

    await refreshPorts();
    final selectedPortName = _selectedPort?.name;
    final port = _resolveConnectionPort(selectedPortName);
    if (port == null || port.isEmpty) {
      _statusMessage =
          'No Proxmark3 port detected. Reconnect device and refresh ports.';
      _busy = false;
      notifyListeners();
      return;
    }

    try {
      if (selectedPortName != null && selectedPortName != port) {
        _console.add(
          ConsoleEntry('Switching to preferred callout port: $port'),
        );
      }
      final args = <String>['-p', port];
      final workingDir = _coreManager.guessWorkingDir(_coreInfo.path);
      await _pm3Service.start(
        executable: _coreInfo.path!,
        args: args,
        workingDirectory: workingDir,
        onExit: _handlePm3Exit,
      );
      _connected = true;
      _statusMessage = 'Connecting to $port...';
      _console.add(ConsoleEntry('Connecting to $port...'));
      Future.delayed(const Duration(milliseconds: 600), () {
        if (_connected) {
          sendCommand('hw version');
        }
      });
    } catch (error) {
      _statusMessage = 'Failed to start pm3: $error';
    }

    _busy = false;
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (!_connected) return;
    _scanMode = ReadScanMode.none;
    _scanInProgress = false;
    _lastScanStartedAt = null;
    _continuousScanTimer?.cancel();
    _continuousScanTimer = null;
    await _pm3Service.stop();
    _connected = false;
    notifyListeners();
  }

  void sendCommand(String command) {
    if (command.trim().isEmpty) return;
    _console.add(ConsoleEntry('pm3 → $command'));
    _pm3Service.send(command.trim());
    notifyListeners();
  }

  Future<void> startReadScan() async {
    await startHfScan();
  }

  Future<void> startLfReadScan() async {
    await startLfScan();
  }

  Future<void> startHfScan() async {
    await _startScan(
      mode: ReadScanMode.hfSingle,
      command: 'hf search',
      status: 'Scanning HF tags...',
    );
  }

  Future<void> startLfScan() async {
    await _startScan(
      mode: ReadScanMode.lfSingle,
      command: 'lf search',
      status: 'Scanning LF tags...',
    );
  }

  Future<void> startContinuousHfScan() async {
    await _startScan(
      mode: ReadScanMode.hfContinuous,
      command: 'hf search',
      status: 'Continuous HF scan running...',
    );
  }

  Future<void> startContinuousLfScan() async {
    await _startScan(
      mode: ReadScanMode.lfContinuous,
      command: 'lf search',
      status: 'Continuous LF scan running...',
    );
  }

  Future<void> startEmvScan() async {
    await _startScan(
      mode: ReadScanMode.emvSingle,
      command: 'emv scan',
      status: 'Scanning EMV card...',
    );
  }

  Future<void> _startScan({
    required ReadScanMode mode,
    required String command,
    required String status,
  }) async {
    if (!_connected) {
      _statusMessage = 'Connect to Proxmark3 before starting a read scan.';
      notifyListeners();
      return;
    }

    _scanMode = mode;
    _scanInProgress = false;
    _lastScanStartedAt = null;
    _statusMessage = status;
    _configureContinuousTicker();
    _triggerScanCommand(command);
    notifyListeners();
  }

  Future<void> stopReadScan() async {
    _scanMode = ReadScanMode.none;
    _continuousScanTimer?.cancel();
    _continuousScanTimer = null;
    _lastScanStartedAt = null;
    if (!_connected) {
      _scanInProgress = false;
      notifyListeners();
      return;
    }
    _scanInProgress = false;
    _statusMessage = 'Scan stopped.';
    _pm3Service.interrupt();
    notifyListeners();
  }

  void clearConsole() {
    _console.clear();
    notifyListeners();
  }

  Future<void> checkForUpdates() async {
    _busy = true;
    _statusMessage = 'Checking for updates...';
    notifyListeners();

    try {
      _latestUpdate = await _updateService.fetchLatestStable();
      if (_latestUpdate == null) {
        _statusMessage = 'No compatible release assets found.';
      } else {
        _statusMessage = 'Core source: ${_latestUpdate!.name}';
      }
    } catch (error) {
      _statusMessage = 'Update check failed: $error';
    }

    _busy = false;
    notifyListeners();
  }

  Future<void> installLatestUpdate() async {
    if (_latestUpdate == null) return;
    _busy = true;
    _statusMessage = 'Downloading core from GitHub...';
    _resetDownloadProgress();
    notifyListeners();

    try {
      final path = await _updateService.install(
        _latestUpdate!,
        onProgress: _handleDownloadProgress,
      );
      if (path == null) {
        _statusMessage = 'Update download failed.';
      } else {
        await _coreManager.writeCurrent(
          path: path,
          version: _latestUpdate!.tag,
        );
        await refreshCore();
        _statusMessage = 'Core updated to ${_latestUpdate!.tag}.';
      }
    } catch (error) {
      _statusMessage = 'Update install failed: $error';
    }

    _busy = false;
    _resetDownloadProgress();
    notifyListeners();
  }

  Future<void> downloadLatestCore() async {
    if (_busy) return;
    await checkForUpdates();
    if (_latestUpdate != null) {
      await installLatestUpdate();
    } else {
      _statusMessage =
          'No compatible online binary found in latest release assets. Import a local core binary.';
      notifyListeners();
    }
  }

  Future<void> _autoDownloadCore() async {
    if (_busy) return;
    _busy = true;
    _statusMessage = 'Downloading core...';
    _resetDownloadProgress();
    notifyListeners();
    try {
      _latestUpdate = await _updateService.fetchLatestStable();
      if (_latestUpdate != null) {
        final path = await _updateService.install(
          _latestUpdate!,
          onProgress: _handleDownloadProgress,
        );
        if (path != null) {
          await _coreManager.writeCurrent(
            path: path,
            version: _latestUpdate!.tag,
          );
          await refreshCore();
          _statusMessage = 'Core downloaded.';
        } else {
          _statusMessage = 'Auto-download failed.';
        }
      } else {
        _statusMessage = 'No compatible release found.';
      }
    } catch (error) {
      _statusMessage = 'Auto-download failed: $error';
    }
    _busy = false;
    _resetDownloadProgress();
    notifyListeners();
  }

  Future<void> importCoreFromFile({bool setAsCurrent = true}) async {
    _busy = true;
    _statusMessage = 'Opening file picker...';
    notifyListeners();

    try {
      final file = await openFile();
      if (file == null) {
        _statusMessage = 'Import cancelled.';
        _busy = false;
        notifyListeners();
        return;
      }

      final path = await _coreManager.importCore(
        File(file.path),
        setAsCurrent: setAsCurrent,
      );
      if (path == null) {
        _statusMessage = 'Import failed.';
      } else {
        if (setAsCurrent) {
          await refreshCore();
          _statusMessage = 'Core imported successfully.';
        } else {
          _statusMessage = 'Core added to local library.';
        }
      }
    } catch (error) {
      _statusMessage = 'Import failed: $error';
    }

    _busy = false;
    notifyListeners();
  }

  Future<void> addSeparateCoreFromFile() async {
    await importCoreFromFile(setAsCurrent: false);
  }

  Future<void> downloadExperimentalCore() async {
    if (_busy) return;
    _busy = true;
    _statusMessage = 'Checking for experimental updates...';
    _resetDownloadProgress();
    notifyListeners();

    try {
      final experimental = await _updateService.fetchLatestExperimental();
      if (experimental == null) {
        _statusMessage = 'No compatible experimental release found.';
      } else {
        _latestUpdate = experimental;
        final path = await _updateService.install(
          experimental,
          onProgress: _handleDownloadProgress,
        );
        if (path == null) {
          _statusMessage = 'Experimental core download failed.';
        } else {
          await _coreManager.writeCurrent(
            path: path,
            version: experimental.tag,
          );
          await refreshCore();
          _statusMessage = 'Experimental core installed (${experimental.tag}).';
        }
      }
    } catch (error) {
      _statusMessage = 'Experimental core install failed: $error';
    }

    _busy = false;
    _resetDownloadProgress();
    notifyListeners();
  }

  Future<void> runCommandChain(
    List<String> commands, {
    Duration stepDelay = const Duration(milliseconds: 850),
  }) async {
    final cleaned = commands
        .map((command) => command.trim())
        .where((command) => command.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) return;
    if (!_connected) {
      _statusMessage = 'Connect to Proxmark3 before running command chains.';
      notifyListeners();
      return;
    }

    _statusMessage = 'Running ${cleaned.length} queued command(s)...';
    notifyListeners();

    for (var i = 0; i < cleaned.length; i += 1) {
      if (!_connected) {
        _statusMessage = 'Command chain stopped: device disconnected.';
        notifyListeners();
        return;
      }
      sendCommand(cleaned[i]);
      if (i < cleaned.length - 1) {
        await Future.delayed(stepDelay);
      }
    }

    _statusMessage = 'Command chain sent (${cleaned.length} commands).';
    notifyListeners();
  }

  Future<void> openDocumentation() async {
    const url = 'https://github.com/RfidResearchGroup/proxmark3/wiki';
    try {
      if (Platform.isMacOS) {
        await Process.start('open', [url]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
      } else {
        _console.add(ConsoleEntry('Documentation: $url'));
      }
      _statusMessage = 'Opened Proxmark documentation.';
    } catch (_) {
      _statusMessage = 'Unable to open browser. Documentation: $url';
      _console.add(ConsoleEntry('Documentation: $url'));
    }
    notifyListeners();
  }

  Future<void> openSupportLink() async {
    const url = 'https://buymeacoffee.com/einnovoeg';
    try {
      if (Platform.isMacOS) {
        await Process.start('open', [url]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
      } else {
        _console.add(ConsoleEntry('Support: $url'));
      }
      _statusMessage = 'Opened support link.';
    } catch (_) {
      _statusMessage = 'Unable to open browser. Support: $url';
      _console.add(ConsoleEntry('Support: $url'));
    }
    notifyListeners();
  }

  Future<File> _settingsFile() async {
    final supportDir = await getApplicationSupportDirectory();
    return File('${supportDir.path}/settings.json');
  }

  Future<void> _loadSettings() async {
    try {
      final file = await _settingsFile();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, dynamic>) {
          _onboardingDismissed = data['onboardingDismissed'] == true;
          final mode = data['themeMode'] as String?;
          _themeMode = switch (mode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          _accentPalette = AppPalette.paletteFromName(
            data['accentPalette'] as String?,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final file = await _settingsFile();
      await file.writeAsString(
        jsonEncode({
          'onboardingDismissed': _onboardingDismissed,
          'themeMode': _themeMode.name,
          'accentPalette': AppPalette.paletteName(_accentPalette),
        }),
      );
    } catch (_) {}
  }

  void _handleDownloadProgress(int received, int total) {
    _downloadStart ??= DateTime.now();
    _downloadReceived = received;
    _downloadTotal = total;
    if (total > 0) {
      _downloadProgress = received / total;
    } else {
      _downloadProgress = null;
    }
    final elapsed = DateTime.now().difference(_downloadStart!).inMilliseconds;
    if (elapsed > 0) {
      _downloadSpeed = received / (elapsed / 1000.0);
    }
    notifyListeners();
  }

  void _resetDownloadProgress() {
    _downloadReceived = 0;
    _downloadTotal = 0;
    _downloadProgress = null;
    _downloadStart = null;
    _downloadSpeed = null;
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }
    final precision = size < 10 && unitIndex > 0 ? 1 : 0;
    return '${size.toStringAsFixed(precision)} ${units[unitIndex]}';
  }

  void _handleOutput(ConsoleEntry entry) {
    final cleanLine = entry.message.replaceAll(
      RegExp(r'\x1B\[[0-9;]*[A-Za-z]'),
      '',
    );
    final line = cleanLine.toLowerCase();
    if (line.contains('using uart port')) {
      _statusMessage = entry.message;
    }
    if (line.contains('connected to') && line.contains('proxmark')) {
      _statusMessage = 'Connected to hardware.';
    }
    if (line.contains('invalid serial port')) {
      _statusMessage =
          'Selected serial port is invalid: ${_selectedPort?.name ?? 'unknown'}';
      _connected = false;
      _scanMode = ReadScanMode.none;
      _scanInProgress = false;
      _lastScanStartedAt = null;
      _continuousScanTimer?.cancel();
      _continuousScanTimer = null;
    }
    if ((line.contains('failed to connect') && line.contains('proxmark')) ||
        line.contains('failed to connect to hardware') ||
        line.contains('no proxmark') ||
        (line.contains('not found') && line.contains('proxmark'))) {
      _statusMessage = entry.message;
      if (_connected) {
        _connected = false;
      }
      _scanMode = ReadScanMode.none;
      _scanInProgress = false;
      _lastScanStartedAt = null;
      _continuousScanTimer?.cancel();
      _continuousScanTimer = null;
    }
    if (line.contains('searching for') ||
        line.contains('hf search') ||
        line.contains('lf search') ||
        line.contains('emv scan') ||
        line.contains('emv reader')) {
      _scanInProgress = true;
    }
    if (line.contains('done') ||
        line.contains('no known tags') ||
        line.contains('no tags found') ||
        line.contains('aborted') ||
        line.contains('interrupt')) {
      _scanInProgress = false;
      _lastScanStartedAt = null;
    }
    if (_isContinuousMode(_scanMode) && line.contains('pm3 -->')) {
      _scanInProgress = false;
      _lastScanStartedAt = null;
    }

    final uidMatch = RegExp(
      r'\b(?:uid|id)\s*[:=]\s*([0-9a-fA-F: \-]{4,})',
      caseSensitive: false,
    ).firstMatch(cleanLine);
    if (uidMatch != null) {
      final rawUid = uidMatch.group(1)?.trim();
      if (rawUid != null && rawUid.isNotEmpty) {
        _lastReadUid = rawUid.replaceAll(RegExp(r'\s+'), '');
        if (_recentReadUids.isEmpty || _recentReadUids.first != _lastReadUid) {
          _recentReadUids.insert(0, _lastReadUid!);
          if (_recentReadUids.length > 8) {
            _recentReadUids.removeLast();
          }
        }
        _scanInProgress = false;
        _lastScanStartedAt = null;
      }
    }

    final typeMatch = RegExp(
      r'(mifare|iso14443a|iso14443b|ntag|desfire|t55xx|hid|em410x|emv)',
      caseSensitive: false,
    ).firstMatch(cleanLine);
    if (typeMatch != null) {
      _lastReadType = typeMatch.group(1)?.toUpperCase();
    }

    final sakMatch = RegExp(
      r'\bsak\s*[:=]\s*(0x[0-9a-fA-F]+)',
      caseSensitive: false,
    ).firstMatch(cleanLine);
    if (sakMatch != null) {
      _lastReadSak = sakMatch.group(1);
    }

    final atqaMatch = RegExp(
      r'\batqa\s*[:=]\s*(0x[0-9a-fA-F]+)',
      caseSensitive: false,
    ).firstMatch(cleanLine);
    if (atqaMatch != null) {
      _lastReadAtqa = atqaMatch.group(1);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _continuousScanTimer?.cancel();
    _continuousScanTimer = null;
    _consoleSub?.cancel();
    _pm3Service.dispose();
    super.dispose();
  }

  void _handlePm3Exit(int exitCode) {
    if (_disposed) return;
    _connected = false;
    _scanMode = ReadScanMode.none;
    _continuousScanTimer?.cancel();
    _continuousScanTimer = null;
    _scanInProgress = false;
    _lastScanStartedAt = null;
    if (exitCode != 0) {
      _statusMessage = 'pm3 exited with code $exitCode';
    }
    notifyListeners();
  }

  bool _isContinuousMode(ReadScanMode mode) {
    return mode == ReadScanMode.hfContinuous ||
        mode == ReadScanMode.lfContinuous;
  }

  void _configureContinuousTicker() {
    _continuousScanTimer?.cancel();
    _continuousScanTimer = null;
    if (!_isContinuousMode(_scanMode)) return;

    _continuousScanTimer = Timer.periodic(const Duration(milliseconds: 900), (
      _,
    ) {
      if (_disposed || !_connected || !_isContinuousMode(_scanMode)) {
        _continuousScanTimer?.cancel();
        _continuousScanTimer = null;
        return;
      }

      if (_scanInProgress) {
        final startedAt = _lastScanStartedAt;
        if (startedAt != null &&
            DateTime.now().difference(startedAt) < const Duration(seconds: 4)) {
          return;
        }
        _scanInProgress = false;
        _lastScanStartedAt = null;
      }

      if (_scanMode == ReadScanMode.hfContinuous) {
        _triggerScanCommand('hf search');
      } else if (_scanMode == ReadScanMode.lfContinuous) {
        _triggerScanCommand('lf search');
      }
    });
  }

  void _triggerScanCommand(String command) {
    if (!_connected) return;
    _scanInProgress = true;
    final startedAt = DateTime.now();
    _lastScanStartedAt = startedAt;
    sendCommand(command);
    Future.delayed(const Duration(seconds: 4), () {
      if (_disposed || !_connected) return;
      if (_lastScanStartedAt != startedAt || !_scanInProgress) return;
      _scanInProgress = false;
      _lastScanStartedAt = null;
      if (_isContinuousMode(_scanMode)) {
        _statusMessage = _scanMode == ReadScanMode.hfContinuous
            ? 'Continuous HF scan running...'
            : 'Continuous LF scan running...';
      } else {
        _statusMessage = 'Scan completed.';
      }
      notifyListeners();
    });
  }

  SerialPortInfo? _findPreferredPort(List<SerialPortInfo> ports) {
    if (ports.isEmpty) return null;
    const priorityPatterns = [
      'usbmodemiceman',
      'sbmodemiceman',
      'iceman',
      'proxmark',
      'usbmodem',
      'usbserial',
    ];
    for (final pattern in priorityPatterns) {
      for (final port in ports) {
        final haystack = [
          port.name,
          port.description ?? '',
          port.manufacturer ?? '',
          port.serialNumber ?? '',
        ].join(' ').toLowerCase();
        if (haystack.contains(pattern)) {
          return port;
        }
      }
    }
    return ports.first;
  }

  String? _resolveConnectionPort(String? selectedPortName) {
    if (selectedPortName == null || selectedPortName.isEmpty) return null;
    if (!Platform.isMacOS) return selectedPortName;
    if (!selectedPortName.startsWith('/dev/tty.')) {
      return selectedPortName;
    }

    final suffix = selectedPortName.substring('/dev/tty.'.length);
    final calloutName = '/dev/cu.$suffix';
    final hasCallout = _ports.any((port) => port.name == calloutName);
    if (hasCallout) {
      return calloutName;
    }
    return selectedPortName;
  }
}
