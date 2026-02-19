import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/console_entry.dart';

class Pm3Service {
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final _controller = StreamController<ConsoleEntry>.broadcast();
  void Function(int exitCode)? _onExit;
  Completer<void>? _stopCompleter;
  bool _isStopping = false;

  Stream<ConsoleEntry> get output => _controller.stream;

  bool get isRunning => _process != null;

  Future<void> start({
    required String executable,
    required List<String> args,
    String? workingDirectory,
    void Function(int exitCode)? onExit,
  }) async {
    if (_process != null) return;
    _isStopping = false;
    _stopCompleter = null;
    _onExit = onExit;
    _process = await Process.start(
      executable,
      args,
      runInShell: false,
      workingDirectory: workingDirectory,
    );

    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _safeAdd(ConsoleEntry(line)));

    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _safeAdd(ConsoleEntry(line, isError: true)));

    _process!.exitCode.then((code) {
      _safeAdd(ConsoleEntry('pm3 exited with code $code'));
      _process = null;
      _isStopping = false;
      _onExit?.call(code);
      _stopCompleter?.complete();
      _stopCompleter = null;
      unawaited(_stdoutSub?.cancel());
      unawaited(_stderrSub?.cancel());
      _stdoutSub = null;
      _stderrSub = null;
    });
  }

  void send(String command) {
    if (_process == null) return;
    _process!.stdin.writeln(command);
  }

  void interrupt() {
    if (_process == null) return;
    try {
      _process!.stdin.add(const [3]);
      _process!.stdin.flush();
    } catch (_) {
      // Best-effort interrupt.
    }
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    if (_isStopping) {
      await _stopCompleter?.future;
      return;
    }

    _isStopping = true;
    _stopCompleter = Completer<void>();

    try {
      process.stdin.writeln('exit');
      await process.stdin.flush();
    } catch (_) {
      // Process may have already closed stdin.
    }

    final exitedGracefully = await _waitForExit(
      process,
      const Duration(milliseconds: 700),
    );
    if (!exitedGracefully) {
      process.kill(ProcessSignal.sigterm);
      final exitedAfterSigterm = await _waitForExit(
        process,
        const Duration(milliseconds: 700),
      );
      if (!exitedAfterSigterm) {
        process.kill(ProcessSignal.sigkill);
      }
    }

    await _stopCompleter?.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process = null;
    _isStopping = false;
    _stopCompleter = null;
  }

  void dispose() {
    unawaited(stop());
    _controller.close();
  }

  void _safeAdd(ConsoleEntry entry) {
    if (_controller.isClosed) return;
    _controller.add(entry);
  }

  Future<bool> _waitForExit(Process process, Duration timeout) async {
    final result = await Future.any<bool>([
      process.exitCode.then((_) => true),
      Future<bool>.delayed(timeout, () => false),
    ]);
    return result;
  }
}
