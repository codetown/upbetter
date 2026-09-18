// 开发期校验脚本：验证 ImageProbe 能正确解析各类图像头。
// 用法：dart run tool/probe_check.dart <文件...>
import 'dart:io';

import 'package:upbetter/src/core/image/image_probe.dart';

Future<void> main(List<String> args) async {
  for (final path in args) {
    final info = await ImageProbe.probe(path);
    stdout.writeln('${info ?? '解析失败'}  <-  $path');
  }
}
