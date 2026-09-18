import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:upbetter/src/core/app_paths.dart';
import 'package:upbetter/src/core/models.dart';
import 'package:upbetter/src/core/runtime/downloader.dart';
import 'package:upbetter/src/core/runtime/runtime_manager.dart';

/// 联网测试默认不跑：CI 环境未必能访问 GitHub，
/// 而一个必然失败的测试比没有测试更糟。本地用环境变量显式打开。
final bool _networkTestsEnabled =
    Platform.environment['UPBETTER_NETWORK_TESTS'] == '1';

/// 运行时安装流程的测试。
///
/// 解压逻辑决定了「首次启动能不能正常用起来」，而它恰恰是最容易被
/// 发行包结构变化搞坏的一环，因此用一份贴近真实布局的压缩包把筛选规则钉住。
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('upbetter_runtime');
    AppPaths.initWithRoot(root);
  });

  tearDown(() async {
    AppPaths.portableRuntimeOverride = null;
    if (root.existsSync()) await root.delete(recursive: true);
  });

  group('发行包解压', () {
    test('提取可执行文件、依赖库与模型，跳过示例素材', () async {
      final zip = File(p.join(root.path, 'runtime.zip'));
      await zip.writeAsBytes(_fakeArchive());

      extractArchive(
        zip.path,
        AppPaths.runtime.path,
        AppPaths.models.path,
        'realesrgan-ncnn-vulkan.exe',
      );

      // 运行时可执行文件与依赖库应当就位。
      expect(File(p.join(AppPaths.runtime.path, 'realesrgan-ncnn-vulkan.exe')).existsSync(), isTrue);
      expect(File(p.join(AppPaths.runtime.path, 'vcomp140.dll')).existsSync(), isTrue);

      // 模型权重应当被放进 models 目录。
      for (final model in kBuiltinModels) {
        expect(
          File(p.join(AppPaths.models.path, model.binFile)).existsSync(),
          isTrue,
          reason: '缺少 ${model.binFile}',
        );
        expect(
          File(p.join(AppPaths.models.path, model.paramFile)).existsSync(),
          isTrue,
          reason: '缺少 ${model.paramFile}',
        );
      }

      // 发行包里附带的示例素材不应被解压出来。
      for (final junk in ['README_windows.md', 'onepiece_demo.mp4', 'input.jpg', 'input2.jpg']) {
        expect(
          File(p.join(AppPaths.runtime.path, junk)).existsSync(),
          isFalse,
          reason: '$junk 不应被解压',
        );
        expect(File(p.join(AppPaths.models.path, junk)).existsSync(), isFalse);
      }
    });

    test('压缩包缺少可执行文件时抛出明确的错误', () async {
      final zip = File(p.join(root.path, 'broken.zip'));
      final archive = Archive()
        ..add(ArchiveFile.bytes('models/realesrgan-x4plus.bin', Uint8List(64)));
      await zip.writeAsBytes(ZipEncoder().encodeBytes(archive));

      expect(
        () => extractArchive(
          zip.path,
          AppPaths.runtime.path,
          AppPaths.models.path,
          'realesrgan-ncnn-vulkan.exe',
        ),
        throwsA(isA<DownloadException>()),
      );
    });
  });

  group('运行时状态', () {
    test('引擎缺失时报告未安装', () async {
      final runtime = RuntimeManager();
      await runtime.refresh();
      expect(runtime.stage, RuntimeStage.absent);
      expect(runtime.isReady, isFalse);
      runtime.dispose();
    });

    test('引擎与模型就位后被发现', () async {
      await _installFakeRuntime(root);

      final runtime = RuntimeManager();
      await runtime.refresh();

      expect(runtime.stage, RuntimeStage.ready);
      expect(runtime.isReady, isTrue);
      expect(runtime.models.value.length, kBuiltinModels.length);
      expect(
        runtime.models.value.map((m) => m.id).toSet(),
        kBuiltinModels.map((m) => m.id).toSet(),
      );
      runtime.dispose();
    });

    test('模型文件不完整时不会把该模型列为可用', () async {
      await _installFakeRuntime(root);
      // 删掉某个模型的一个文件，模拟手动清理残留。
      await File(p.join(AppPaths.models.path, 'realesrgan-x4plus.param')).delete();

      final runtime = RuntimeManager();
      await runtime.refresh();

      expect(runtime.isReady, isTrue);
      expect(runtime.models.value.map((m) => m.id), isNot(contains('realesrgan-x4plus')));
      expect(runtime.models.value.length, kBuiltinModels.length - 1);
      runtime.dispose();
    });
  });

  group('真实下载与安装', () {
    test('下载官方发行包并完成安装', () async {
      final runtime = RuntimeManager();
      await runtime.refresh();
      expect(runtime.stage, RuntimeStage.absent);

      final progressSamples = <double>[];
      final speedSamples = <double>[];
      void listener() {
        progressSamples.add(runtime.progress);
        speedSamples.add(runtime.bytesPerSecond);
      }

      runtime.addListener(listener);
      await runtime.install();
      runtime.removeListener(listener);

      expect(runtime.stage, RuntimeStage.ready, reason: runtime.errorMessage ?? '安装未完成');
      expect(runtime.isReady, isTrue);

      // 可执行文件与全部内置模型都应就位。
      expect(File(runtime.binaryPath).existsSync(), isTrue);
      expect(runtime.models.value.length, kBuiltinModels.length);

      // 下载过程中进度必须单调不减，并且最终到达 1。
      expect(progressSamples, isNotEmpty);
      for (var i = 1; i < progressSamples.length; i++) {
        expect(
          progressSamples[i],
          greaterThanOrEqualTo(progressSamples[i - 1] - 0.001),
          reason: '进度出现了回退',
        );
      }
      expect(progressSamples.last, closeTo(1, 0.001));

      // 应当至少上报过一次有效速度。
      expect(speedSamples.any((s) => s > 0), isTrue, reason: '从未上报下载速度');

      runtime.dispose();
    }, timeout: const Timeout(Duration(minutes: 15)));
  }, skip: _networkTestsEnabled ? null : '设置 UPBETTER_NETWORK_TESTS=1 以启用联网测试');

  group('下载来源', () {
    test('默认以官方直连打头，并准备了镜像回退', () {
      final sources = RuntimeManager.downloadSources();
      expect(sources.first, contains('github.com'));
      expect(sources.first, contains('realesrgan-ncnn-vulkan'));
      expect(sources.length, greaterThan(1), reason: '应当有镜像作为回退');
      expect(sources.toSet().length, sources.length, reason: '来源不应重复');
    });

    test('自定义来源优先级最高', () {
      final sources = RuntimeManager.downloadSources(
        customSource: 'https://my.mirror/runtime.zip',
      );
      expect(sources.first, 'https://my.mirror/runtime.zip');
      expect(sources, contains(contains('github.com')));
    });

    test('空白自定义来源会被忽略', () {
      final sources = RuntimeManager.downloadSources(customSource: '   ');
      expect(sources.first, contains('github.com'));
    });

    test('镜像前缀拼接出完整的 GitHub 地址', () {
      final sources = RuntimeManager.downloadSources();
      for (final source in sources.skip(1)) {
        expect(source, contains('github.com/xinntao/Real-ESRGAN'));
        expect(Uri.tryParse(source)?.hasScheme, isTrue, reason: '$source 不是合法 URL');
      }
    });
  });

  group('SHA-256 校验', () {
    test('对已知内容算出稳定摘要', () async {
      final file = File(p.join(root.path, 'digest.bin'));
      await file.writeAsString('upbetter');

      final digest = await Downloader.computeSha256(file);
      expect(digest, hasLength(64));
      // 同样的内容必须得到同样的摘要，否则校验机制形同虚设。
      expect(digest, await Downloader.computeSha256(file));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(digest), isTrue);
    });

    test('文件不存在时返回空串而不是抛错', () async {
      final missing = File(p.join(root.path, 'nope.bin'));
      expect(await Downloader.computeSha256(missing), isEmpty);
    });
  });
}

/// 用假的二进制内容搭出一个结构正确的运行时目录树。
Future<void> _installFakeRuntime(Directory root) async {
  final archive = File(p.join(root.path, 'seed.zip'));
  await archive.writeAsBytes(_fakeArchive());
  extractArchive(
    archive.path,
    AppPaths.runtime.path,
    AppPaths.models.path,
    'realesrgan-ncnn-vulkan.exe',
  );
}

/// 构造一个与官方发行包结构一致的压缩包（内容为占位数据）。
Uint8List _fakeArchive() {
  final archive = Archive();

  void add(String name, int size) =>
      archive.add(ArchiveFile.bytes(name, Uint8List(size)..fillRange(0, size, 7)));

  add('realesrgan-ncnn-vulkan.exe', 4096);
  add('vcomp140.dll', 512);
  add('vcomp140d.dll', 512);
  for (final model in kBuiltinModels) {
    add('models/${model.binFile}', 2048);
    add('models/${model.paramFile}', 256);
  }
  // 发行包里确实存在、但我们不需要的素材。
  add('README_windows.md', 128);
  add('onepiece_demo.mp4', 1024);
  add('input.jpg', 256);
  add('input2.jpg', 256);

  return ZipEncoder().encodeBytes(archive);
}
