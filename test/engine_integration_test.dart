import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:upbetter/src/core/app_paths.dart';
import 'package:upbetter/src/core/engine/upscale_engine.dart';
import 'package:upbetter/src/core/image/image_probe.dart';
import 'package:upbetter/src/core/models.dart';
import 'package:upbetter/src/core/runtime/runtime_manager.dart';
import 'package:upbetter/src/core/settings.dart';
import 'package:upbetter/src/core/util/log.dart';

/// 真实的端到端测试：驱动 Real-ESRGAN 推理进程，验证
/// 批次暂存、硬链接、进度解析、产物搬运与命名解析整条链路。
///
/// 需要本地存在推理引擎才能运行（`.devtools/runtime`），
/// 否则整组测试会被跳过——CI 上也不应该因为没有 GPU 而变红。
void main() {
  final runtimeDir = Directory(p.join(Directory.current.path, '.devtools', 'runtime'));
  final binary = File(p.join(runtimeDir.path, 'realesrgan-ncnn-vulkan.exe'));
  final available = binary.existsSync();

  if (!available) {
    test('引擎端到端测试', () {
      // ignore: avoid_print
      print('跳过：未找到 ${binary.path}，请先运行 tool/install_dev_runtime 下载引擎。');
    }, skip: '本地未安装推理引擎');
    return;
  }

  late Directory workDir;
  late RuntimeManager runtime;
  late UpscaleEngine engine;
  late AppSettings settings;

  setUpAll(() async {
    workDir = await Directory.systemTemp.createTemp('upbetter_e2e');
    AppPaths.initWithRoot(Directory(p.join(workDir.path, 'appdata')));
    AppPaths.portableRuntimeOverride = runtimeDir.absolute.path;

    runtime = RuntimeManager();
    await runtime.refresh();
  });

  // 每个测试用全新的引擎与设置。
  //
  // 共用同一个引擎会引入测试间的隐性耦合：上一个测试的收尾（进程回收、
  // 暂存目录清理）与下一个测试的启动存在竞态，表现为随机失败。
  setUp(() async {
    settings = await AppSettings.load();
    // 用最快的模型，让端到端测试保持在可接受的时间内。
    settings.options = const UpscaleOptions(
      modelId: 'realesr-animevideov3',
      scale: 2,
      format: OutputFormat.png,
    );
    engine = UpscaleEngine(runtime: runtime, settings: settings);
  });

  tearDown(() async {
    engine.dispose();
    await settings.flush();
    settings.dispose();
  });

  tearDownAll(() async {
    runtime.dispose();
    if (workDir.existsSync()) {
      await workDir.delete(recursive: true);
    }
  });

  test('运行时可用且能发现内置模型', () {
    expect(runtime.isReady, isTrue);
    expect(runtime.models.value.length, greaterThanOrEqualTo(3));
    expect(
      runtime.models.value.map((m) => m.id),
      containsAll(['realesrgan-x4plus', 'realesrgan-x4plus-anime', 'realesr-animevideov3']),
    );
  });

  test('单文件放大产出正确尺寸的结果', () async {
    final source = File(p.join(workDir.path, 'single.png'));
    await source.writeAsBytes(await makePng(64, 48));

    final job = engine.createJob(
      inputPath: source.path,
      sourceInfo: (await ImageProbe.probe(source.path))!,
      options: settings.options,
    );
    engine.addJobs([job]);
    engine.start();

    await waitAllDone(engine, [job], timeout: const Duration(minutes: 3));
    if (job.status.value != JobStatus.done) _dumpLog();

    expect(job.status.value, JobStatus.done, reason: job.errorMessage.value ?? '');
    final output = File(job.outputPath.value!);
    expect(output.existsSync(), isTrue);

    final info = await ImageProbe.probe(output.path);
    expect(info!.width, 128);
    expect(info.height, 96);
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('多个同参数文件合并为一个批次且全部产出', () async {
    final inputs = <File>[];
    for (var i = 0; i < 3; i++) {
      final file = File(p.join(workDir.path, 'batch_$i.png'));
      await file.writeAsBytes(await makePng(48 + i * 8, 40));
      inputs.add(file);
    }
    final launchesBefore = engine.processLaunchCount;

    final jobs = <UpscaleJob>[];
    for (final file in inputs) {
      jobs.add(engine.createJob(
        inputPath: file.path,
        sourceInfo: (await ImageProbe.probe(file.path))!,
        options: settings.options,
      ));
    }
    engine.addJobs(jobs);
    engine.start();

    await waitAllDone(engine, jobs, timeout: const Duration(minutes: 5));

    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      expect(job.status.value, JobStatus.done, reason: job.errorMessage.value ?? '');
      final info = await ImageProbe.probe(job.outputPath.value!);
      expect(info!.width, (48 + i * 8) * 2);
      expect(info.height, 80);
      // 每个任务的输出路径必须互不相同，否则说明命名去重失效。
      expect(jobs.map((j) => j.outputPath.value).toSet().length, jobs.length);
    }

    // 核心性能断言：3 个同参数文件只应启动 1 次推理进程，
    // 也就是模型权重只加载一次。这是批量处理最主要的优化。
    expect(
      engine.processLaunchCount - launchesBefore,
      1,
      reason: '同参数任务应当合并为单次进程调用',
    );
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('处理顺序遵循用户排序，而不是批次大小', () async {
    // A 是单独一组（3×），B 和 C 同组（2×）。
    // 「最大批次优先」会先跑 B+C，而用户期望的是先跑排在前面的 A。
    final optionsA = settings.options.copyWith(scale: 3);
    final optionsB = settings.options.copyWith(scale: 2);

    Future<UpscaleJob> make(String name, UpscaleOptions options) async {
      final file = File(p.join(workDir.path, name));
      await file.writeAsBytes(await makePng(48, 40));
      return engine.createJob(
        inputPath: file.path,
        sourceInfo: (await ImageProbe.probe(file.path))!,
        options: options,
      );
    }

    final a = await make('order_a.png', optionsA);
    final b = await make('order_b.png', optionsB);
    final c = await make('order_c.png', optionsB);

    final completionOrder = <String>[];
    for (final job in [a, b, c]) {
      job.status.addListener(() {
        if (job.status.value == JobStatus.done) completionOrder.add(job.inputName);
      });
    }

    engine.addJobs([a, b, c]);
    engine.start();
    await waitAllDone(engine, [a, b, c]);

    expect(completionOrder.length, 3, reason: '三个任务都应完成');
    expect(
      completionOrder.first,
      'order_a.png',
      reason: '排在队首的任务应当最先完成',
    );
  }, timeout: const Timeout(Duration(minutes: 7)));

  test('取消排队中的任务后它不会被执行', () async {
    Future<UpscaleJob> make(String name) async {
      final file = File(p.join(workDir.path, name));
      await file.writeAsBytes(await makePng(56, 48));
      return engine.createJob(
        inputPath: file.path,
        sourceInfo: (await ImageProbe.probe(file.path))!,
        options: settings.options,
      );
    }

    final keep = await make('keep.png');
    final drop = await make('drop.png');

    engine.addJobs([keep, drop]);
    engine.cancelJob(drop);
    engine.start();

    await waitAllDone(engine, [keep], timeout: const Duration(minutes: 3));

    expect(keep.status.value, JobStatus.done, reason: keep.errorMessage.value ?? '');
    expect(drop.status.value, JobStatus.canceled);
    expect(drop.outputPath.value == null || !File(drop.outputPath.value!).existsSync(), isTrue,
        reason: '被取消的任务不应产出文件');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('处理完成后暂存目录被清理', () async {
    final batchDir = Directory(p.join(AppPaths.cache.path, 'batch'));
    if (!batchDir.existsSync()) return;

    // 清理是 fire-and-forget 的，给它一点时间落地，否则会读到中间状态。
    await _waitFor(
      () => batchDir.existsSync() && batchDir.listSync().isEmpty,
      timeout: const Duration(seconds: 10),
    );
    expect(batchDir.listSync(), isEmpty);
  });
}

/// 失败时把引擎日志打到测试输出里，否则「进程静默失败」几乎无从排查。
void _dumpLog() {
  // ignore: avoid_print
  print('──── 引擎日志 ────');
  for (final entry in Log.recent) {
    // ignore: avoid_print
    print(entry);
  }
  // ignore: avoid_print
  print('─────────────────');
}

/// 等待这些任务全部结束，并且引擎回到空闲。
///
/// 只等任务状态是不够的：运行循环的收尾（清理暂存目录、复位状态）
/// 发生在任务状态变更之后，不等它就会让测试和收尾逻辑产生竞态。
Future<void> waitAllDone(
  UpscaleEngine engineRef,
  Iterable<UpscaleJob> jobs, {
  Duration timeout = const Duration(minutes: 6),
}) async {
  await _waitFor(() => jobs.every((j) => j.status.value.isTerminal), timeout: timeout);
  await _waitFor(
    () => engineRef.state.value == QueueState.idle,
    timeout: const Duration(seconds: 30),
  );
}

Future<void> _waitFor(bool Function() predicate, {required Duration timeout}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('等待超时（${timeout.inSeconds}s）');
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
}

/// 生成一张真实的 PNG。
///
/// 直接借用 Flutter 自己的编码器，而不是手写 PNG 字节流——
/// 手写的版本很容易在 zlib 流上出错，而推理引擎只会回一句
/// `decode image failed`，排查代价很高。
///
/// 内容用渐变填充而非纯色，这样放大后能看出模型确实重建了细节。
Future<Uint8List> makePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        const [Color(0xFF1E3A8A), Color(0xFFF59E0B)],
      ),
  );
  // 加几条细线，给超分模型一些真实的边缘可以重建。
  final linePaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..strokeWidth = 1;
  for (var i = 1; i < 5; i++) {
    final y = height * i / 5;
    canvas.drawLine(Offset(0, y), Offset(width.toDouble(), y), linePaint);
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();

  return data!.buffer.asUint8List();
}
