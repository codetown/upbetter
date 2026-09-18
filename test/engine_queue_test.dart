import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:upbetter/src/core/app_paths.dart';
import 'package:upbetter/src/core/engine/upscale_engine.dart';
import 'package:upbetter/src/core/image/image_probe.dart';
import 'package:upbetter/src/core/models.dart';
import 'package:upbetter/src/core/runtime/runtime_manager.dart';
import 'package:upbetter/src/core/settings.dart';

/// 队列编排逻辑的测试。这些行为完全不涉及推理进程，因此可以跑得很快。
void main() {
  late Directory root;
  late RuntimeManager runtime;
  late UpscaleEngine engine;
  late AppSettings settings;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('upbetter_queue');
    AppPaths.initWithRoot(root);

    runtime = RuntimeManager();
    settings = await AppSettings.load();
    engine = UpscaleEngine(runtime: runtime, settings: settings);
  });

  tearDown(() async {
    engine.dispose();
    settings.dispose();
    runtime.dispose();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  UpscaleJob addJob(String name, {UpscaleOptions? options}) {
    final job = engine.createJob(
      inputPath: p.join(root.path, name),
      sourceInfo: ImageInfo(
        width: 100,
        height: 80,
        format: ImageFormat.png,
        fileSize: 1024,
      ),
      options: options ?? const UpscaleOptions(),
    );
    engine.addJobs([job]);
    return job;
  }

  List<String> queueNames() => engine.jobs.map((j) => j.inputName).toList();

  group('入队', () {
    test('按加入顺序排列', () {
      addJob('a.png');
      addJob('b.png');
      addJob('c.png');
      expect(queueNames(), ['a.png', 'b.png', 'c.png']);
    });

    test('同路径同参数的重复任务不会重复入队', () {
      addJob('a.png');
      addJob('a.png');
      expect(engine.jobs.length, 1);
    });

    test('同路径但参数不同的任务可以共存', () {
      addJob('a.png', options: const UpscaleOptions(scale: 2));
      addJob('a.png', options: const UpscaleOptions(scale: 4));
      expect(engine.jobs.length, 2);
    });
  });

  group('排序', () {
    test('下标是「移除旧位置之后」的目标位置', () {
      addJob('a.png');
      addJob('b.png');
      addJob('c.png');

      // 把队首挪到末尾。
      engine.reorderJob(0, 2);
      expect(queueNames(), ['b.png', 'c.png', 'a.png']);
    });

    test('向前拖动', () {
      addJob('a.png');
      addJob('b.png');
      addJob('c.png');

      engine.reorderJob(2, 0);
      expect(queueNames(), ['c.png', 'a.png', 'b.png']);
    });

    test('拖回原位不改变顺序', () {
      addJob('a.png');
      addJob('b.png');
      engine.reorderJob(0, 0);
      expect(queueNames(), ['a.png', 'b.png']);
      engine.reorderJob(1, 1);
      expect(queueNames(), ['a.png', 'b.png']);
    });

    test('越界下标被安全忽略', () {
      addJob('a.png');
      engine.reorderJob(5, 0);
      engine.reorderJob(0, 99);
      expect(engine.jobs.length, 1);
    });
  });

  group('取消任务', () {
    test('取消排队中的任务后不再计入待处理', () {
      final job = addJob('a.png');
      addJob('b.png');
      expect(engine.pendingCount, 2);

      engine.cancelJob(job);

      expect(job.status.value, JobStatus.canceled);
      expect(job.progress.value, 0);
      expect(engine.pendingCount, 1);
      expect(engine.hasWork, isTrue, reason: '仍有 b.png 待处理');
    });

    test('取消已终止的任务是空操作', () {
      final job = addJob('a.png');
      job.status.value = JobStatus.done;
      engine.cancelJob(job);
      expect(job.status.value, JobStatus.done);
    });

    test('已取消的任务不会被重新排队', () {
      final job = addJob('a.png');
      engine.cancelJob(job);
      // 模拟批次回滚：只有状态仍为 running 的任务会被放回队列。
      expect(job.status.value.isTerminal, isTrue);
      expect(engine.pendingCount, 0);
    });

    test('重试能把已取消的任务放回队列', () {
      final job = addJob('a.png');
      engine.cancelJob(job);
      expect(engine.hasWork, isFalse);

      engine.retryFailed();

      expect(job.status.value, JobStatus.queued);
      expect(engine.hasWork, isTrue);
    });
  });

  group('参数同步', () {
    test('修改参数会同步到所有排队中的任务', () {
      final queued = addJob('a.png');
      final done = addJob('b.png');
      done.status.value = JobStatus.done;

      const updated = UpscaleOptions(modelId: 'realesrgan-x4plus-anime', scale: 2);
      engine.applyOptionsToPending(updated);

      expect(queued.options.modelId, 'realesrgan-x4plus-anime');
      expect(queued.options.scale, 2);
      expect(done.options.modelId, 'realesrgan-x4plus',
          reason: '已完成的任务应保留它当时使用的参数');
    });

    test('参数未变化时不做无意义的通知', () {
      addJob('a.png', options: const UpscaleOptions(modelId: 'm', scale: 4));
      var notifications = 0;
      engine.addListener(() => notifications++);

      engine.applyOptionsToPending(const UpscaleOptions(modelId: 'm', scale: 4));

      expect(notifications, 0);
    });
  });

  group('清理', () {
    test('清除已完成只移除终止状态的任务', () {
      final a = addJob('a.png');
      final b = addJob('b.png');
      final c = addJob('c.png');
      a.status.value = JobStatus.done;
      b.status.value = JobStatus.failed;

      engine.clearFinished();

      expect(queueNames(), ['c.png']);
      expect(c.status.value, JobStatus.queued);
    });

    test('清空队列会移除所有任务', () {
      addJob('a.png');
      addJob('b.png');
      engine.clearAll();
      expect(engine.jobs, isEmpty);
      expect(engine.overallProgress.value, 0);
    });
  });

  group('耗时预估', () {
    test('没有历史数据时不给出估计', () {
      expect(engine.estimateDuration(const UpscaleOptions(), 1000000), isNull);
    });

    test('有实测吞吐量时按像素数换算', () {
      settings.recordThroughput('realesrgan-x4plus|4|-1', 100000); // 100k 像素/秒
      final estimate = engine.estimateDuration(
        const UpscaleOptions(modelId: 'realesrgan-x4plus', scale: 4, gpuId: -1),
        1000000,
      );
      expect(estimate, isNotNull);
      expect(estimate!.inSeconds, 10);
    });

    test('不同倍率的估计互相独立', () {
      settings.recordThroughput('realesrgan-x4plus|4|-1', 100000);
      final other = engine.estimateDuration(
        const UpscaleOptions(modelId: 'realesrgan-x4plus', scale: 2, gpuId: -1),
        1000000,
      );
      expect(other, isNull, reason: '2× 还没有实测数据');
    });
  });
}
