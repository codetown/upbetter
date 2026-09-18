import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../app_paths.dart';

enum LogLevel { debug, info, warn, error }

class LogEntry {
  LogEntry(this.level, this.tag, this.message) : time = DateTime.now();

  final LogLevel level;
  final String tag;
  final String message;
  final DateTime time;

  @override
  String toString() {
    final t = time.toIso8601String().substring(11, 23);
    final lv = level.name.toUpperCase().padRight(5);
    return '$t $lv [$tag] $message';
  }
}

/// 极简日志器。
///
/// 设计目标：**绝不阻塞调用方**。写盘通过微任务批量合并，
/// 内存里只保留最近 [maxEntries] 条供界面的日志面板读取。
class Log {
  Log._();

  static const int maxEntries = 500;

  static final Queue<LogEntry> _recent = Queue<LogEntry>();
  static final StreamController<LogEntry> _stream = StreamController<LogEntry>.broadcast();

  static IOSink? _sink;
  static final List<String> _pending = <String>[];
  static bool _flushScheduled = false;

  static Stream<LogEntry> get stream => _stream.stream;
  static List<LogEntry> get recent => _recent.toList(growable: false);

  static void initFile() {
    try {
      _sink = AppPaths.logFile.openWrite(mode: FileMode.append);
    } on Object {
      _sink = null;
    }
  }

  static void d(String tag, String message) => _add(LogLevel.debug, tag, message);
  static void i(String tag, String message) => _add(LogLevel.info, tag, message);
  static void w(String tag, String message) => _add(LogLevel.warn, tag, message);
  static void e(String tag, String message, [Object? error, StackTrace? stack]) {
    final buf = StringBuffer(message);
    if (error != null) buf.write('\n  ↳ $error');
    if (stack != null) buf.write('\n$stack');
    _add(LogLevel.error, tag, buf.toString());
  }

  static void _add(LogLevel level, String tag, String message) {
    final entry = LogEntry(level, tag, message);
    _recent.addLast(entry);
    while (_recent.length > maxEntries) {
      _recent.removeFirst();
    }
    if (!_stream.isClosed) _stream.add(entry);

    _pending.add(entry.toString());
    _scheduleFlush();
  }

  static void _scheduleFlush() {
    if (_flushScheduled || _sink == null) return;
    _flushScheduled = true;
    // 合并同一事件循环内的所有写入，避免高频日志拖慢推理进度回调。
    scheduleMicrotask(() {
      _flushScheduled = false;
      if (_pending.isEmpty) return;
      final chunk = '${_pending.join('\n')}\n';
      _pending.clear();
      try {
        _sink?.write(chunk);
      } on Object {
        // 日志失败不应影响主流程。
      }
    });
  }

  static Future<void> dispose() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } on Object {
      // ignore
    }
    _sink = null;
    await _stream.close();
  }
}
