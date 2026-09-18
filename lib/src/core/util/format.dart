import 'dart:math' as math;

/// 轻量格式化工具，全部为纯函数，可在任意 isolate 中调用。
class Fmt {
  Fmt._();

  static const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

  /// `1.42 GB`
  static String bytes(int value) {
    if (value <= 0) return '0 B';
    var size = value.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < _units.length - 1) {
      size /= 1024;
      unit++;
    }
    final digits = size >= 100 || unit == 0 ? 0 : (size >= 10 ? 1 : 2);
    return '${size.toStringAsFixed(digits)} ${_units[unit]}';
  }

  /// `1.42 GB/s`
  static String byteRate(double bytesPerSecond) => '${bytes(bytesPerSecond.round())}/s';

  /// `00:42` / `1:02:03`
  static String duration(Duration d) {
    final total = d.inSeconds.clamp(0, 359999);
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '${mm.padLeft(2, '0')}:$ss';
  }

  /// `2.4s` / `1m 12s`
  static String compactDuration(Duration d) {
    if (d.inSeconds < 60) {
      final secs = d.inMilliseconds / 1000;
      return '${secs.toStringAsFixed(secs >= 10 ? 1 : 2)}s';
    }
    return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
  }

  /// `1920 × 1080`
  static String dimensions(int width, int height) =>
      '${_thousands(width)} × ${_thousands(height)}';

  /// 像素总量，例如 `2.1 MP`。
  static String megapixels(int width, int height) {
    final mp = width * height / 1000000;
    return '${mp.toStringAsFixed(mp >= 100 ? 0 : 1)} MP';
  }

  static String _thousands(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// 缩放倍数，例如 `×4` / `×2.5`
  static String scale(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.05) return '×${rounded.toInt()}';
    return '×${value.toStringAsFixed(1)}';
  }

  /// 裁剪过长的文件路径，保留头尾。用于狭窄的 UI 空间。
  static String ellipsisPath(String path, {int maxChars = 48}) {
    if (path.length <= maxChars) return path;
    final head = maxChars ~/ 3;
    final tail = maxChars - head - 1;
    return '${path.substring(0, head)}…${path.substring(path.length - tail)}';
  }

  static String percent(double value, {int digits = 0}) =>
      '${(value * 100).clamp(0, 1).toStringAsFixed(digits)}%';

  /// 把秒数格式化为「剩余约 1 分 20 秒」中的数字部分。
  static String eta(Duration d) {
    if (d.inSeconds <= 1) return '即将完成';
    if (d.inSeconds < 60) return '剩余 ${d.inSeconds} 秒';
    return '剩余 ${d.inMinutes} 分 ${(d.inSeconds % 60).toString().padLeft(2, '0')} 秒';
  }

  static double clamp01(double v) => v.isNaN ? 0 : math.min(1, math.max(0, v));
}
