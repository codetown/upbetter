import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';

/// 输出路径与文件名模板的解析。
class OutputResolver {
  OutputResolver._();

  /// 模板可用变量：`{name}` `{scale}` `{model}` `{date}` `{time}` `{w}` `{h}`
  static const Map<String, String> templateTokens = {
    '{name}': '原文件名（不含扩展名）',
    '{scale}': '放大倍率，如 4x',
    '{model}': '模型名称',
    '{date}': '日期，如 20260918',
    '{time}': '时间，如 143052',
    '{w}': '输出宽度',
    '{h}': '输出高度',
  };

  static String renderTemplate(String template, UpscaleJob job, DateTime now) {
    final base = p.basenameWithoutExtension(job.inputName);
    final modelId = job.options.modelId;
    final result = template
        .replaceAll('{name}', base)
        .replaceAll('{scale}', '${job.options.scale}x')
        .replaceAll('{model}', modelId)
        .replaceAll('{date}', _date(now))
        .replaceAll('{time}', _time(now))
        .replaceAll('{w}', '${job.outputWidth}')
        .replaceAll('{h}', '${job.outputHeight}');

    final sanitized = _sanitize(result);
    return sanitized.isEmpty ? '${base}_upbetter' : sanitized;
  }

  /// 计算某个任务的最终输出文件路径。
  ///
  /// [reserved] 用于在批量场景下避免同一批次内的任务互相覆盖。
  static String resolve(
    UpscaleJob job, {
    required DateTime now,
    Set<String>? reserved,
  }) {
    final options = job.options;
    final dir = _outputDir(job, options);
    final stem = renderTemplate(options.namingTemplate, job, now);
    final ext = options.format.extensionFor(job.sourceInfo.format);
    final candidate = p.join(dir, '$stem.$ext');

    if (options.overwrite) return candidate;
    if (!_isTaken(candidate, reserved)) return candidate;

    // 追加数字后缀，直到找到空闲名字。
    for (var i = 1; i < 10000; i++) {
      final next = p.join(dir, '$stem ($i).$ext');
      if (!_isTaken(next, reserved)) return next;
    }
    return p.join(dir, '$stem.${DateTime.now().microsecondsSinceEpoch}.$ext');
  }

  static bool _isTaken(String path, Set<String>? reserved) {
    if (reserved != null && reserved.contains(path.toLowerCase())) return true;
    return File(path).existsSync();
  }

  static String _outputDir(UpscaleJob job, UpscaleOptions options) {
    switch (options.location) {
      case OutputLocation.alongside:
        return job.inputDir;
      case OutputLocation.subfolder:
        final sub = _sanitize(options.subfolderName);
        return p.join(job.inputDir, sub.isEmpty ? 'upbetter' : sub);
      case OutputLocation.custom:
        final dir = options.outputDir;
        if (dir == null || dir.trim().isEmpty) return job.inputDir;
        return dir;
    }
  }

  /// 去除 Windows 文件名中的非法字符。
  static String _sanitize(String value) {
    return value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
  }

  static String _date(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}';

  static String _time(DateTime t) =>
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  static String _two(int v) => v.toString().padLeft(2, '0');
}
