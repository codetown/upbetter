import 'dart:math' as math;
import 'dart:ui' as ui;

/// 按最长边上限解码图像。
///
/// 使用 [ui.ImmutableBuffer.fromFilePath] + [ui.ImageDescriptor]，
/// 让解码器直接从文件流读取并按目标尺寸解码，避免先把整个文件读进内存。
///
/// 放在 core 层是因为它是「读取图像信息」能力的一部分（同 [ImageProbe]），
/// 界面只需要拿结果绘制即可，具体怎么解码与界面无关。
Future<ui.Image?> decodeImageCapped(String path, int maxEdge) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromFilePath(path);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    final longest = math.max(width, height);

    int? targetWidth;
    int? targetHeight;
    if (longest > maxEdge) {
      if (width >= height) {
        targetWidth = maxEdge;
      } else {
        targetHeight = maxEdge;
      }
    }

    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  } on Object {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
