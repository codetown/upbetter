import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_paths.dart';
import 'models.dart';
import 'util/log.dart';

/// 应用设置。整体持久化为一个 JSON 文件，写入做了防抖合并。
class AppSettings extends ChangeNotifier {
  AppSettings._(this._raw);

  final Map<String, Object?> _raw;
  Timer? _saveTimer;
  bool _disposed = false;

  static Future<AppSettings> load() async {
    Map<String, Object?> raw = {};
    final file = AppPaths.settingsFile;
    try {
      if (file.existsSync()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, Object?>) raw = decoded;
      }
    } on Object catch (error) {
      Log.w('Settings', '读取设置失败，使用默认值：$error');
    }
    return AppSettings._(raw);
  }

  // ── 主题 ────────────────────────────────────────────────────────────────

  ThemeMode get themeMode => switch (_raw['themeMode'] as String?) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  set themeMode(ThemeMode value) => _set('themeMode', value.name);

  /// 强调色种子。默认与应用图标同色，让开箱即用的观感是统一的。
  int get accentSeed => (_raw['accentSeed'] as num?)?.toInt() ?? 0xFF2563EB;

  set accentSeed(int value) => _set('accentSeed', value);

  // ── 放大参数 ────────────────────────────────────────────────────────────

  UpscaleOptions get options {
    final raw = _raw['options'];
    if (raw is Map) {
      return UpscaleOptions.fromJson(raw.cast<String, Object?>());
    }
    return const UpscaleOptions();
  }

  set options(UpscaleOptions value) => _set('options', value.toJson());

  // ── 性能 ────────────────────────────────────────────────────────────────

  /// 同时运行的推理进程数。同一块 GPU 上并行收益有限，默认 1。
  int get concurrency => ((_raw['concurrency'] as num?)?.toInt() ?? 1).clamp(1, 3);

  set concurrency(int value) => _set('concurrency', value.clamp(1, 3));

  /// 处理期间阻止系统休眠。
  bool get preventSleep => _raw['preventSleep'] as bool? ?? true;

  set preventSleep(bool value) => _set('preventSleep', value);

  /// 完成后自动打开输出目录。
  bool get revealWhenDone => _raw['revealWhenDone'] as bool? ?? false;

  set revealWhenDone(bool value) => _set('revealWhenDone', value);

  /// 完成后播放提示音。
  bool get playSoundWhenDone => _raw['playSoundWhenDone'] as bool? ?? true;

  set playSoundWhenDone(bool value) => _set('playSoundWhenDone', value);

  // ── 吞吐量记忆 ──────────────────────────────────────────────────────────
  //
  // 记录每种「模型+倍率+GPU」组合的实测像素吞吐（像素/秒）。
  // 有了它，进度条在第一次运行的最初几秒就能给出准确的剩余时间，
  // 而不是先显示「计算中」再突然跳到结果。

  Map<String, double> get _throughput {
    final raw = _raw['throughput'];
    if (raw is Map) {
      return raw.map((k, v) => MapEntry('$k', (v as num).toDouble()));
    }
    return const {};
  }

  double? throughputFor(String key) => _throughput[key];

  void recordThroughput(String key, double pixelsPerSecond) {
    if (pixelsPerSecond <= 0 || !pixelsPerSecond.isFinite) return;
    final current = _throughput;
    final previous = current[key];
    // 指数滑动平均，抑制单次抖动。
    final next = previous == null ? pixelsPerSecond : previous * 0.6 + pixelsPerSecond * 0.4;
    final updated = Map<String, double>.from(current)..[key] = next;
    // 只保留最近使用的 24 条，避免设置文件无限膨胀。
    if (updated.length > 24) {
      updated.remove(updated.keys.first);
    }
    _set('throughput', updated);
  }

  // ── 下载 ────────────────────────────────────────────────────────────────

  /// 自定义的引擎下载地址。留空则使用内置的直连与镜像列表。
  ///
  /// 面向网络受限的环境：用户可以填入自己信任的镜像或离线包地址，
  /// 下载完成后仍会做 SHA-256 校验。
  String get downloadSource => _raw['downloadSource'] as String? ?? '';

  set downloadSource(String value) => _set('downloadSource', value);

  // ── 窗口 ────────────────────────────────────────────────────────────────

  Rect? get windowBounds {
    final raw = _raw['windowBounds'];
    if (raw is! Map) return null;
    final l = (raw['l'] as num?)?.toDouble();
    final t = (raw['t'] as num?)?.toDouble();
    final w = (raw['w'] as num?)?.toDouble();
    final h = (raw['h'] as num?)?.toDouble();
    if (l == null || t == null || w == null || h == null) return null;
    if (w < 800 || h < 560) return null;
    return Rect.fromLTWH(l, t, w, h);
  }

  set windowBounds(Rect? value) {
    if (value == null) return;
    _set('windowBounds', {
      'l': value.left,
      't': value.top,
      'w': value.width,
      'h': value.height,
    });
  }

  bool get windowMaximized => _raw['windowMaximized'] as bool? ?? false;

  set windowMaximized(bool value) => _set('windowMaximized', value);

  // ── 最近使用 ────────────────────────────────────────────────────────────

  List<String> get recentOutputDirs {
    final raw = _raw['recentOutputDirs'];
    if (raw is List) return raw.whereType<String>().take(6).toList();
    return const [];
  }

  void rememberOutputDir(String dir) {
    final list = [dir, ...recentOutputDirs.where((d) => d != dir)];
    _set('recentOutputDirs', list.take(6).toList());
  }

  // ── 内部 ────────────────────────────────────────────────────────────────

  void _set(String key, Object? value) {
    _raw[key] = value;
    if (_disposed) return;
    notifyListeners();
    _scheduleSave();
  }

  /// 高频写入（如窗口拖动、吞吐量更新）会被合并成一次落盘。
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  Future<void> _saveNow() async {
    if (_disposed) return;
    try {
      final tmp = File('${AppPaths.settingsFile.path}.tmp');
      await tmp.writeAsString(jsonEncode(_raw), flush: true);
      await tmp.rename(AppPaths.settingsFile.path);
    } on Object catch (error) {
      Log.w('Settings', '保存设置失败：$error');
    }
  }

  /// 立即落盘，用于应用退出前。
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _saveNow();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    super.dispose();
  }
}
