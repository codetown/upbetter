import 'dart:io';

import 'package:path/path.dart' as p;

/// 与操作系统外壳交互的小工具。
class SystemShell {
  SystemShell._();

  /// 在资源管理器中定位并选中文件。
  static Future<void> revealFile(String path) async {
    if (!Platform.isWindows) return;
    // explorer 对参数格式很敏感：必须使用反斜杠，且路径整体作为一个参数。
    final normalized = p.normalize(path);
    await Process.run('explorer.exe', ['/select,', normalized]);
  }

  /// 打开目录。
  static Future<void> openDirectory(String path) async {
    if (!Platform.isWindows) return;
    final dir = Directory(path);
    if (!dir.existsSync()) await dir.create(recursive: true);
    await Process.run('explorer.exe', [p.normalize(path)]);
  }

}
