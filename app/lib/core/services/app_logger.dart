import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Severity level of a log entry.
enum LogLevel { debug, info, warn, error }

/// Singleton file logger used to capture detailed runtime traces, especially
/// during the video processing pipeline (upload / poll / download).
///
/// Behavior:
/// - Calls before [init] succeed are still printed via [debugPrint] but are
///   buffered and flushed to disk once initialization completes. This keeps
///   tests safe (which never call [init]) while preserving early-startup logs
///   in production.
/// - Each log file is capped at [_maxBytes]. When full, the active file is
///   rotated to `app.1.log` (older rotations shift up to [_maxRotations]).
/// - Writes are serialized through a single Future chain so the file remains
///   well-formed even when many call sites log concurrently.
class AppLogger {
  AppLogger._();

  static final AppLogger _instance = AppLogger._();
  static AppLogger get instance => _instance;

  static const String _logFileName = 'app.log';
  static const String _logDirName = 'logs';
  static const int _maxBytes = 1 * 1024 * 1024; // 1 MB
  static const int _maxRotations = 3;
  static const int _bufferLimit = 200;

  final Queue<String> _pendingBeforeInit = Queue<String>();
  Future<void> _writeChain = Future<void>.value();
  Directory? _logDir;
  File? _logFile;
  bool _initialized = false;
  bool _initializing = false;

  /// Returns the directory holding rotated log files, or null when [init] has
  /// not run successfully (e.g. inside unit tests).
  Directory? get logDirectory => _logDir;

  /// Returns the path of the active log file, or null when uninitialized.
  String? get currentLogPath => _logFile?.path;

  /// Initialize the logger. Safe to call multiple times; subsequent calls are
  /// no-ops. Failures are swallowed because logging must never crash the app.
  Future<void> init() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/$_logDirName');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _logDir = dir;
      _logFile = File('${dir.path}/$_logFileName');

      _initialized = true;
      // Flush anything buffered before init completed.
      if (_pendingBeforeInit.isNotEmpty) {
        final pending = _pendingBeforeInit.toList();
        _pendingBeforeInit.clear();
        for (final line in pending) {
          _enqueueWrite(line);
        }
      }
      i('AppLogger', 'logger initialized at ${_logFile!.path}');
    } catch (error, stack) {
      // Initialization failed (e.g. no platform channel in tests). Stay in
      // console-only mode and surface the failure during debug runs.
      debugPrint('[AppLogger] init failed: $error\n$stack');
      _initialized = false;
    } finally {
      _initializing = false;
    }
  }

  void d(String tag, String message) => log(LogLevel.debug, tag, message);
  void i(String tag, String message) => log(LogLevel.info, tag, message);
  void w(String tag, String message, [Object? error, StackTrace? stack]) =>
      log(LogLevel.warn, tag, message, error, stack);
  void e(String tag, String message, [Object? error, StackTrace? stack]) =>
      log(LogLevel.error, tag, message, error, stack);

  /// Core entry point. Builds a single line and dispatches it to console +
  /// file (when ready) or buffers it until init runs.
  void log(
    LogLevel level,
    String tag,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    final timestamp = DateTime.now().toIso8601String();
    final levelTag = _levelTag(level);
    final buffer = StringBuffer('$timestamp [$levelTag] [$tag] $message');
    if (error != null) buffer.write(' | error=$error');
    if (stack != null) buffer.write('\n$stack');
    final line = buffer.toString();

    debugPrint(line);

    if (!_initialized) {
      // Cap pre-init buffer to keep memory bounded if init never runs.
      if (_pendingBeforeInit.length >= _bufferLimit) {
        _pendingBeforeInit.removeFirst();
      }
      _pendingBeforeInit.add(line);
      return;
    }

    _enqueueWrite(line);
  }

  void _enqueueWrite(String line) {
    _writeChain = _writeChain.then((_) => _writeLine(line));
  }

  Future<void> _writeLine(String line) async {
    final file = _logFile;
    if (file == null) return;
    try {
      if (await file.exists()) {
        final size = await file.length();
        if (size + line.length + 1 > _maxBytes) {
          await _rotate(file);
        }
      }
      await file.writeAsString('$line\n', mode: FileMode.append, flush: false);
    } catch (error, stack) {
      debugPrint('[AppLogger] write failed: $error\n$stack');
    }
  }

  Future<void> _rotate(File file) async {
    final dir = _logDir;
    if (dir == null) return;
    try {
      // Drop the oldest rotation, then shift `app.(n-1).log` -> `app.n.log`.
      for (var i = _maxRotations; i >= 1; i--) {
        final older = File('${dir.path}/app.$i.log');
        if (i == _maxRotations && await older.exists()) {
          await older.delete();
          continue;
        }
        final younger = i == 1 ? file : File('${dir.path}/app.${i - 1}.log');
        if (await younger.exists()) {
          await younger.rename('${dir.path}/app.$i.log');
        }
      }
    } catch (error, stack) {
      debugPrint('[AppLogger] rotate failed: $error\n$stack');
    }
  }

  /// Best-effort flush (the write chain already serializes IO; this just
  /// awaits whatever is in flight). Useful before reading log contents.
  Future<void> flush() async {
    await _writeChain;
  }

  String _levelTag(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'D';
      case LogLevel.info:
        return 'I';
      case LogLevel.warn:
        return 'W';
      case LogLevel.error:
        return 'E';
    }
  }
}

/// Convenience accessor used across the codebase.
AppLogger get appLogger => AppLogger.instance;
