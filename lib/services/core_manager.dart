import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/core_info.dart';

class CoreManager {
  Future<CoreInfo> resolveCore() async {
    final supportDir = await getApplicationSupportDirectory();
    final coreRoot = Directory('${supportDir.path}/core');
    if (!await coreRoot.exists()) {
      await coreRoot.create(recursive: true);
    }

    final currentFile = File('${coreRoot.path}/current.json');
    if (await currentFile.exists()) {
      final data = jsonDecode(await currentFile.readAsString());
      if (data is Map<String, dynamic>) {
        final path = data['path'] as String?;
        final version = data['version'] as String?;
        if (path != null && await File(path).exists()) {
          return CoreInfo(
            path: path,
            source: CoreSource.updated,
            versionLabel: version,
          );
        }
      }
    }

    final embedded = await _extractEmbedded(coreRoot);
    if (embedded != null) {
      return CoreInfo(
        path: embedded,
        source: CoreSource.embedded,
        versionLabel: 'embedded',
      );
    }

    final systemBundled = await _bootstrapFromSystem(coreRoot);
    if (systemBundled != null) {
      await writeCurrent(path: systemBundled, version: 'system-bundled');
      return CoreInfo(
        path: systemBundled,
        source: CoreSource.system,
        versionLabel: 'system-bundled',
      );
    }

    return const CoreInfo(path: null, source: CoreSource.missing);
  }

  Future<void> writeCurrent({
    required String path,
    required String version,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final coreRoot = Directory('${supportDir.path}/core');
    if (!await coreRoot.exists()) {
      await coreRoot.create(recursive: true);
    }
    final currentFile = File('${coreRoot.path}/current.json');
    await currentFile.writeAsString(
      jsonEncode({'path': path, 'version': version}),
    );
  }

  Future<String?> importCore(
    File file, {
    String? versionLabel,
    bool setAsCurrent = true,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final coreRoot = Directory('${supportDir.path}/core');
    if (!await coreRoot.exists()) {
      await coreRoot.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final importDir = Directory('${coreRoot.path}/imported/$timestamp');
    await importDir.create(recursive: true);

    final executableName = Platform.isWindows ? 'pm3.exe' : 'pm3';
    final outFile = File('${importDir.path}/$executableName');
    await file.copy(outFile.path);
    await _ensureExecutable(outFile);

    if (setAsCurrent) {
      await writeCurrent(
        path: outFile.path,
        version: versionLabel ?? 'manual-$timestamp',
      );
    }
    return outFile.path;
  }

  Future<String?> _extractEmbedded(Directory coreRoot) async {
    final platform = _platformSlug();
    final arch = _archSlug();
    if (platform == null || arch == null) return null;

    final assetPrefix = 'assets/bundled/$platform/$arch/';
    final assetPaths = await _bundledAssetPaths(assetPrefix);
    if (assetPaths.isEmpty) return null;

    final embeddedDir = Directory('${coreRoot.path}/embedded/$platform-$arch');
    if (!await embeddedDir.exists()) {
      await embeddedDir.create(recursive: true);
    }

    final existing = _resolveEmbeddedEntryPoint(embeddedDir);
    if (existing != null && existing.existsSync()) {
      return existing.path;
    }

    for (final assetPath in assetPaths) {
      final relativePath = assetPath.substring(assetPrefix.length);
      if (relativePath.isEmpty) continue;

      final data = await rootBundle.load(assetPath);
      final outFile = File('${embeddedDir.path}/$relativePath');
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    final executable = _resolveEmbeddedEntryPoint(embeddedDir);
    if (executable == null) return null;
    await _ensureExecutable(executable);
    return executable.path;
  }

  Future<List<String>> _bundledAssetPaths(String prefix) async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final manifest = jsonDecode(manifestContent);
      if (manifest is! Map<String, dynamic>) return const [];
      final assets =
          manifest.keys
              .where((key) => key.startsWith(prefix) && !key.endsWith('/'))
              .toList()
            ..sort();
      return assets;
    } catch (_) {
      return const [];
    }
  }

  File? _resolveEmbeddedEntryPoint(Directory embeddedDir) {
    final candidates = Platform.isWindows
        ? const ['bin/pm3.exe', 'pm3.exe', 'bin/proxmark3.exe', 'proxmark3.exe']
        : const ['bin/pm3', 'pm3', 'bin/proxmark3', 'proxmark3'];
    for (final relative in candidates) {
      final file = File('${embeddedDir.path}/$relative');
      if (file.existsSync()) return file;
    }
    return null;
  }

  Future<void> _ensureExecutable(File file) async {
    if (Platform.isWindows) return;
    await Process.run('chmod', ['+x', file.path]);
  }

  Future<String?> _bootstrapFromSystem(Directory coreRoot) async {
    final candidate = await _findSystemCoreExecutable();
    if (candidate == null) return null;

    final platform = _platformSlug() ?? 'unknown';
    final arch = _archSlug() ?? 'unknown';
    final executableName = Platform.isWindows ? 'pm3.exe' : 'pm3';
    final embeddedDir = Directory('${coreRoot.path}/embedded/$platform-$arch');
    if (!await embeddedDir.exists()) {
      await embeddedDir.create(recursive: true);
    }

    final outFile = File('${embeddedDir.path}/$executableName');
    await File(candidate).copy(outFile.path);
    await _ensureExecutable(outFile);
    return outFile.path;
  }

  Future<String?> _findSystemCoreExecutable() async {
    final candidates = <String>[
      if (Platform.isMacOS) '/opt/homebrew/opt/proxmark3/bin/pm3',
      if (Platform.isMacOS) '/usr/local/opt/proxmark3/bin/pm3',
      if (Platform.isLinux) '/usr/bin/pm3',
      if (Platform.isLinux) '/usr/local/bin/pm3',
      if (Platform.isWindows) r'C:\Program Files\Proxmark3\pm3.exe',
    ];

    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    final whichResult = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      ['pm3'],
    );
    if (whichResult.exitCode == 0) {
      final stdout = (whichResult.stdout as String).trim();
      if (stdout.isNotEmpty) {
        final first = stdout.split(RegExp(r'[\r\n]+')).first.trim();
        if (first.isNotEmpty && await File(first).exists()) {
          return first;
        }
      }
    }
    return null;
  }

  String? guessWorkingDir(String? executablePath) {
    if (executablePath == null || executablePath.isEmpty) return null;
    var file = File(executablePath);
    if (!file.existsSync()) {
      return null;
    }

    final binDir = file.parent;
    if (_hasDataFolders(binDir)) {
      return binDir.path;
    }

    final parent = binDir.parent;
    final clientDir = Directory('${parent.path}/client');
    if (clientDir.existsSync() && _hasDataFolders(clientDir)) {
      return clientDir.path;
    }

    return binDir.path;
  }

  bool _hasDataFolders(Directory dir) {
    return Directory('${dir.path}/resources').existsSync() ||
        Directory('${dir.path}/dictionaries').existsSync() ||
        Directory('${dir.path}/share/proxmark3').existsSync() ||
        Directory('${dir.parent.path}/share/proxmark3').existsSync();
  }

  String? _platformSlug() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return null;
  }

  String? _archSlug() {
    switch (Abi.current()) {
      case Abi.macosArm64:
      case Abi.linuxArm64:
        return 'arm64';
      case Abi.macosX64:
      case Abi.linuxX64:
      case Abi.windowsX64:
        return 'x64';
      default:
        return null;
    }
  }
}
