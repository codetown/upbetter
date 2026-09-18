import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:upbetter/src/core/engine/output_path.dart';
import 'package:upbetter/src/core/image/image_probe.dart';
import 'package:upbetter/src/core/models.dart';
import 'package:upbetter/src/core/runtime/runtime_manager.dart';
import 'package:upbetter/src/core/util/format.dart';

void main() {
  group('ImageProbe 图像头解析', () {
    test('解析 PNG 尺寸', () async {
      final info = await _probeBytes(_png(320, 240), '.png');
      expect(info?.width, 320);
      expect(info?.height, 240);
      expect(info?.format, ImageFormat.png);
    });

    test('解析 JPEG 尺寸（SOF0 段）', () async {
      final info = await _probeBytes(_jpeg(1024, 768), '.jpg');
      expect(info?.width, 1024);
      expect(info?.height, 768);
      expect(info?.format, ImageFormat.jpeg);
    });

    test('JPEG 中包含无关的 APP 段也不会误判', () async {
      final info = await _probeBytes(_jpeg(64, 48, extraAppSegments: 3), '.jpg');
      expect(info?.width, 64);
      expect(info?.height, 48);
    });

    test('无法识别的数据返回 null', () async {
      final info = await _probeBytes(Uint8List.fromList(List.filled(128, 0x41)), '.bin');
      expect(info, isNull);
    });
  });

  group('GPU 设备行解析', () {
    test('从 ncnn 的 verbose 输出中提取设备', () {
      const stderr = '[0 Intel(R) UHD Graphics]  queueC=0[1]  queueG=0[1]  queueT=0[1]\n'
          '[0 Intel(R) UHD Graphics]  bugsbn1=0  bugbilz=0\n'
          '[1 NVIDIA GeForce RTX 4060]  queueC=0[1]\n'
          '0.00%\n25.00%\n';
      final devices = RuntimeManager.parseGpuDevices(stderr);

      expect(devices.length, 2);
      expect(devices[0].index, 0);
      expect(devices[0].name, 'Intel(R) UHD Graphics');
      expect(devices[1].index, 1);
      expect(devices[1].name, 'NVIDIA GeForce RTX 4060');
    });

    test('设备信息重复出现时不会重复计入', () {
      const stderr = '[0 A]  x=1\n[0 A]  x=1\n[0 A]  x=1\n';
      expect(RuntimeManager.parseGpuDevices(stderr).length, 1);
    });

    test('没有设备行时返回空列表', () {
      expect(RuntimeManager.parseGpuDevices('0.00%\n50.00%\n'), isEmpty);
    });
  });

  group('输出路径解析', () {
    test('命名模板替换所有占位符', () {
      final job = _job('/photos/DSC_0421.jpg', 4000, 3000, const UpscaleOptions(scale: 4));
      final rendered = OutputResolver.renderTemplate(
        '{name}_{model}_{scale}',
        job,
        DateTime(2026, 9, 18),
      );
      expect(rendered, 'DSC_0421_realesrgan-x4plus_4x');
    });

    test('模板中的非法文件名字符会被替换', () {
      final job = _job('/photos/a.jpg', 100, 100, const UpscaleOptions());
      final rendered = OutputResolver.renderTemplate('{name}:v1?', job, DateTime(2026, 1, 1));
      expect(rendered, isNot(contains(':')));
      expect(rendered, isNot(contains('?')));
    });

    test('空模板回退到默认命名', () {
      final job = _job('/photos/a.jpg', 100, 100, const UpscaleOptions());
      expect(OutputResolver.renderTemplate('', job, DateTime(2026, 1, 1)), 'a_upbetter');
    });
  });

  group('格式化工具', () {
    test('字节数按 1024 进制换算', () {
      expect(Fmt.bytes(0), '0 B');
      expect(Fmt.bytes(512), '512 B');
      expect(Fmt.bytes(1024), '1.00 KB');
      expect(Fmt.bytes(1536), '1.50 KB');
      expect(Fmt.bytes(1024 * 1024 * 43), '43.0 MB');
    });

    test('尺寸与像素量的分隔符正确', () {
      expect(Fmt.dimensions(1920, 1080), '1,920 × 1,080');
      expect(Fmt.megapixels(4000, 3000), '12.0 MP');
    });

    test('时长格式化为分秒', () {
      expect(Fmt.duration(const Duration(seconds: 42)), '00:42');
      expect(Fmt.duration(const Duration(minutes: 2, seconds: 5)), '02:05');
      expect(Fmt.duration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });

    test('超长路径在中间省略', () {
      final long = 'C:\\${'a' * 200}\\file.png';
      final result = Fmt.ellipsisPath(long, maxChars: 40);
      expect(result.length, lessThanOrEqualTo(41));
      expect(result, contains('…'));
    });
  });

  group('参数等价性', () {
    test('执行参数相同的任务会被归入同一批次', () {
      const a = UpscaleOptions(modelId: 'm', scale: 4, tileSize: 0, gpuId: -1);
      const b = UpscaleOptions(modelId: 'm', scale: 4, tileSize: 0, gpuId: -1);
      const c = UpscaleOptions(modelId: 'm', scale: 2, tileSize: 0, gpuId: -1);
      expect(a.executionKey, b.executionKey);
      expect(a.executionKey, isNot(c.executionKey));
    });

    test('输出相关的参数不影响执行批次划分', () {
      const a = UpscaleOptions(namingTemplate: '{name}_a');
      const b = UpscaleOptions(namingTemplate: '{name}_b');
      expect(a.executionKey, b.executionKey);
    });

    test('JSON 往返保持等价', () {
      const original = UpscaleOptions(
        modelId: 'realesrgan-x4plus-anime',
        scale: 3,
        format: OutputFormat.webp,
        location: OutputLocation.custom,
        outputDir: 'D:\\out',
        tileSize: 128,
        gpuId: 1,
        tta: true,
        overwrite: true,
      );
      final restored = UpscaleOptions.fromJson(original.toJson());
      expect(restored.modelId, original.modelId);
      expect(restored.scale, original.scale);
      expect(restored.format, original.format);
      expect(restored.location, original.location);
      expect(restored.outputDir, original.outputDir);
      expect(restored.tileSize, original.tileSize);
      expect(restored.gpuId, original.gpuId);
      expect(restored.tta, isTrue);
      expect(restored.overwrite, isTrue);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 测试辅助
// ─────────────────────────────────────────────────────────────────────────────

UpscaleJob _job(String path, int width, int height, UpscaleOptions options) {
  return UpscaleJob(
    id: path,
    inputPath: path,
    sourceInfo: ImageInfo(
      width: width,
      height: height,
      format: ImageFormat.jpeg,
      fileSize: 1024,
    ),
    options: options,
  );
}

Future<ImageInfo?> _probeBytes(List<int> bytes, String extension) async {
  final dir = await Directory.systemTemp.createTemp('upbetter_test');
  try {
    final file = File('${dir.path}${Platform.pathSeparator}probe$extension');
    await file.writeAsBytes(bytes);
    return await ImageProbe.probe(file.path);
  } finally {
    await dir.delete(recursive: true);
  }
}

/// 构造一个只有文件头和 IHDR 的最小合法 PNG。
Uint8List _png(int width, int height) {
  final bytes = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final ihdrBody = BytesBuilder()
    ..add('IHDR'.codeUnits)
    ..add(_be32(width))
    ..add(_be32(height))
    ..add([8, 6, 0, 0, 0]);
  final ihdr = ihdrBody.toBytes();

  bytes
    ..add(_be32(ihdr.length))
    ..add(ihdr)
    ..add(_be32(_crc32(ihdr)))
    ..add(_be32(0))
    ..add('IEND'.codeUnits)
    ..add(_be32(_crc32('IEND'.codeUnits)));

  return bytes.toBytes();
}

/// 构造一个含指定尺寸 SOF0 段的 JPEG（不需要真实的图像数据）。
Uint8List _jpeg(int width, int height, {int extraAppSegments = 0}) {
  final bytes = BytesBuilder()..add([0xFF, 0xD8]);
  for (var i = 0; i < extraAppSegments; i++) {
    // APP0 段，长度 6（含长度字段自身）。
    bytes.add([0xFF, 0xE0, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00]);
  }
  bytes.add([0xFF, 0xC0, 0x00, 0x11, 0x08]);
  bytes.add([(height >> 8) & 0xFF, height & 0xFF]);
  bytes.add([(width >> 8) & 0xFF, width & 0xFF]);
  bytes.add(List.filled(8, 0));
  return bytes.toBytes();
}

List<int> _be32(int value) => [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
