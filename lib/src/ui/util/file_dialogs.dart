import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../../core/image/image_probe.dart';

/// 系统文件对话框的薄封装，统一在这里处理过滤条件与类型收窄。
class FileDialogs {
  FileDialogs._();

  static const XTypeGroup _imageGroup = XTypeGroup(
    label: '图像',
    extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'tga', 'gif', 'ppm', 'pgm'],
  );

  static Future<List<String>> pickImages() async {
    final files = await openFiles(acceptedTypeGroups: const [_imageGroup]);
    return files.map((f) => f.path).toList();
  }

  static Future<String?> pickDirectory({String? confirmButtonText}) {
    return getDirectoryPath(confirmButtonText: confirmButtonText ?? '选择');
  }

  static Future<String?> pickExecutable() async {
    const group = XTypeGroup(label: '可执行文件', extensions: ['exe']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    return file?.path;
  }

  /// 递归收集目录下所有受支持的图像文件。
  ///
  /// 只做扩展名筛选与去重，真正的格式校验留给读取文件头时进行。
  /// [maxFiles] 用来防止误拖整个磁盘导致界面卡死。
  static Future<List<String>> collectImages(
    Iterable<String> paths, {
    int maxFiles = 2000,
    bool recursive = true,
  }) async {
    final results = <String>[];
    final seen = <String>{};

    void addFile(File file) {
      if (results.length >= maxFiles) return;
      final ext = p.extension(file.path).toLowerCase();
      if (!kSupportedInputExtensions.contains(ext)) return;
      // 跳过本工具自己产出的中间文件。
      if (file.path.endsWith('.part')) return;
      final key = file.path.toLowerCase();
      if (seen.add(key)) results.add(file.path);
    }

    for (final path in paths) {
      if (results.length >= maxFiles) break;
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        addFile(File(path));
      } else if (type == FileSystemEntityType.directory) {
        final dir = Directory(path);
        try {
          for (final entity in dir.listSync(recursive: recursive, followLinks: false)) {
            if (results.length >= maxFiles) break;
            if (entity is File) addFile(entity);
          }
        } on Object {
          // 权限不足的目录直接跳过，不影响其余文件。
        }
      }
    }
    results.sort();
    return results;
  }
}
