// 从 `assets/icon.png` 生成 Windows 应用图标（多尺寸 ICO）。
//
// 用法：dart run tool/generate_icon.dart
//
// 为什么不直接用 flutter_launcher_icons：它给 Windows 只生成**单尺寸**的
// ICO（一个 256×256 条目）。那样 Windows 只好自己把 256px 缩到 16/24/32px，
// 而系统自带的缩放对细线条和小字很不友好——图标在任务栏和标题栏会糊成一团。
// ICO 格式本身支持在一个文件里塞多张图，Windows 会挑选最接近的尺寸来用，
// 因此这里自己生成 7 档尺寸，保证每个显示场景都是清晰的。
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Windows 会用到的显示尺寸：
/// 16 标题栏/托盘、24 任务栏、32 任务栏高 DPI 与 Alt+Tab、
/// 48 中图标、64/128 大图标、256 超大图标与资源管理器。
const List<int> _sizes = [16, 24, 32, 48, 64, 128, 256];

void main() {
  final projectRoot = Directory.current.path;
  final source = File(p.join(projectRoot, 'assets', 'icon.png'));
  final target = File(
    p.join(projectRoot, 'windows', 'runner', 'resources', 'app_icon.ico'),
  );

  if (!source.existsSync()) {
    stderr.writeln('找不到源图标：${source.path}');
    exitCode = 1;
    return;
  }

  final decoded = img.decodePng(source.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('无法解码 ${source.path}，请确认是合法的 PNG');
    exitCode = 1;
    return;
  }

  if (decoded.width != decoded.height) {
    stderr.writeln(
      '警告：源图标不是正方形（${decoded.width}×${decoded.height}），'
      '图标会被拉伸。建议改成正方形。',
    );
  }

  stdout.writeln('源图标：${decoded.width}×${decoded.height}');

  // 每档尺寸都从原图重新缩放，而不是逐级缩小——逐级缩会累积模糊。
  final frames = <img.Image>[
    for (final size in _sizes)
      img.copyResize(
        decoded,
        width: size,
        height: size,
        // cubic 在缩小图标时能保住边缘锐度；默认的 linear 会让小尺寸发虚。
        interpolation: img.Interpolation.cubic,
      ),
  ];

  // ICO 内部的每张图用 PNG 存储（Windows Vista 起支持），
  // 这样 256×256 不会因为 BMP 未压缩而膨胀到几百 KB。
  final bytes = img.IcoEncoder().encodeImages(frames);

  target.parent.createSync(recursive: true);
  target.writeAsBytesSync(bytes);

  stdout.writeln('已生成 ${target.path}');
  stdout.writeln(
    '包含尺寸：${_sizes.map((s) => '${s}px').join(', ')}  '
    '（共 ${(bytes.length / 1024).toStringAsFixed(1)} KB）',
  );
}
