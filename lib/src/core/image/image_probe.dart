import 'dart:io';
import 'dart:typed_data';

/// 图像元信息。
class ImageInfo {
  const ImageInfo({
    required this.width,
    required this.height,
    required this.format,
    required this.fileSize,
  });

  final int width;
  final int height;
  final ImageFormat format;
  final int fileSize;

  int get pixels => width * height;

  double get aspectRatio => height == 0 ? 1 : width / height;

  @override
  String toString() => '${format.label} ${width}x$height';
}

enum ImageFormat {
  png('PNG', 'png'),
  jpeg('JPEG', 'jpg'),
  webp('WebP', 'webp'),
  bmp('BMP', 'bmp'),
  gif('GIF', 'gif'),
  tiff('TIFF', 'tiff'),
  unknown('未知', 'bin');

  const ImageFormat(this.label, this.extension);

  final String label;
  final String extension;

  static ImageFormat fromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return ImageFormat.png;
      case 'jpg':
      case 'jpeg':
      case 'jpe':
        return ImageFormat.jpeg;
      case 'webp':
        return ImageFormat.webp;
      case 'bmp':
        return ImageFormat.bmp;
      case 'gif':
        return ImageFormat.gif;
      case 'tif':
      case 'tiff':
        return ImageFormat.tiff;
      default:
        return ImageFormat.unknown;
    }
  }
}

/// 支持的输入扩展名（小写，含点）。
const Set<String> kSupportedInputExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.bmp',
  '.tga',
  '.gif',
  '.ppm',
  '.pgm',
};

/// 通过解析文件头读取图像尺寸，**完全不解码像素**。
///
/// 对一个 300 MB 的 TIFF 也只需要读取前 64 KB，耗时在微秒级，
/// 因此可以安全地在 UI isolate 中对成百上千个文件调用。
class ImageProbe {
  ImageProbe._();

  static const int _headerBytes = 64 * 1024;

  static Future<ImageInfo?> probe(String path) async {
    final file = File(path);
    RandomAccessFile? handle;
    try {
      final length = await file.length();
      if (length < 16) return null;

      handle = await file.open();
      final readSize = length < _headerBytes ? length : _headerBytes;
      final header = await handle.read(readSize);
      final dims = _parse(header);
      if (dims == null) return null;

      return ImageInfo(
        width: dims.$1,
        height: dims.$2,
        format: dims.$3,
        fileSize: length,
      );
    } on Object {
      return null;
    } finally {
      try {
        await handle?.close();
      } on Object {
        // ignore
      }
    }
  }

  static (int, int, ImageFormat)? _parse(Uint8List b) {
    if (b.length >= 24 && _match(b, 0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return (_u32be(b, 16), _u32be(b, 20), ImageFormat.png);
    }
    if (b.length >= 10 && b[0] == 0xFF && b[1] == 0xD8) {
      final jpeg = _parseJpeg(b);
      if (jpeg != null) return (jpeg.$1, jpeg.$2, ImageFormat.jpeg);
      return null;
    }
    if (b.length >= 30 && _match(b, 0, [0x52, 0x49, 0x46, 0x46]) && _match(b, 8, [0x57, 0x45, 0x42, 0x50])) {
      final webp = _parseWebp(b);
      if (webp != null) return (webp.$1, webp.$2, ImageFormat.webp);
      return null;
    }
    if (b.length >= 26 && b[0] == 0x42 && b[1] == 0x4D) {
      return (_u32le(b, 18), _u32le(b, 22).abs(), ImageFormat.bmp);
    }
    if (b.length >= 10 && _match(b, 0, [0x47, 0x49, 0x46, 0x38])) {
      return (_u16le(b, 6), _u16le(b, 8), ImageFormat.gif);
    }
    if (b.length >= 8 && (_match(b, 0, [0x49, 0x49, 0x2A, 0x00]) || _match(b, 0, [0x4D, 0x4D, 0x00, 0x2A]))) {
      final tiff = _parseTiff(b);
      if (tiff != null) return (tiff.$1, tiff.$2, ImageFormat.tiff);
      return null;
    }
    return null;
  }

  /// 遍历 JPEG 段，定位 SOFn（Start Of Frame）段读取尺寸。
  static (int, int)? _parseJpeg(Uint8List b) {
    var offset = 2;
    while (offset + 9 < b.length) {
      if (b[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = b[offset + 1];
      // 填充字节 0xFF 跳过。
      if (marker == 0xFF) {
        offset++;
        continue;
      }
      // 无载荷的标记。
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        offset += 2;
        continue;
      }
      if (offset + 4 > b.length) break;
      final segmentLength = _u16be(b, offset + 2);
      if (segmentLength < 2) break;

      final isSof = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        if (offset + 9 > b.length) break;
        return (_u16be(b, offset + 7), _u16be(b, offset + 5));
      }
      offset += 2 + segmentLength;
    }
    return null;
  }

  static (int, int)? _parseWebp(Uint8List b) {
    if (b.length < 30) return null;
    final fourCc = String.fromCharCodes(b.sublist(12, 16));
    switch (fourCc) {
      case 'VP8X':
        final w = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
        final h = 1 + (b[27] | (b[28] << 8) | (b[29] << 16));
        return (w, h);
      case 'VP8 ':
        // 关键帧头：3 字节起始码 + 3 字节同步码，随后 2 字节宽高（14 位有效）。
        if (b.length < 30) return null;
        final w = _u16le(b, 26) & 0x3FFF;
        final h = _u16le(b, 28) & 0x3FFF;
        return (w, h);
      case 'VP8L':
        if (b.length < 25) return null;
        final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
        final w = (bits & 0x3FFF) + 1;
        final h = ((bits >> 14) & 0x3FFF) + 1;
        return (w, h);
      default:
        return null;
    }
  }

  /// 仅支持最常见的 TIFF 布局（IFD0 中的 ImageWidth/ImageLength）。
  static (int, int)? _parseTiff(Uint8List b) {
    final little = b[0] == 0x49;
    int u16(int o) => little ? _u16le(b, o) : _u16be(b, o);
    int u32(int o) => little ? _u32le(b, o) : _u32be(b, o);

    if (b.length < 8) return null;
    final ifdOffset = u32(4);
    if (ifdOffset + 2 > b.length) return null;
    final count = u16(ifdOffset);

    int? width;
    int? height;
    for (var i = 0; i < count; i++) {
      final entry = ifdOffset + 2 + i * 12;
      if (entry + 12 > b.length) break;
      final tag = u16(entry);
      if (tag != 256 && tag != 257) continue;
      final type = u16(entry + 2);
      final value = type == 3 ? u16(entry + 8) : u32(entry + 8);
      if (tag == 256) width = value;
      if (tag == 257) height = value;
    }
    if (width == null || height == null || width <= 0 || height <= 0) return null;
    return (width, height);
  }

  static bool _match(Uint8List b, int offset, List<int> pattern) {
    if (offset + pattern.length > b.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (b[offset + i] != pattern[i]) return false;
    }
    return true;
  }

  static int _u16be(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
  static int _u16le(Uint8List b, int o) => (b[o + 1] << 8) | b[o];
  static int _u32be(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  static int _u32le(Uint8List b, int o) =>
      (b[o + 3] << 24) | (b[o + 2] << 16) | (b[o + 1] << 8) | b[o];
}
