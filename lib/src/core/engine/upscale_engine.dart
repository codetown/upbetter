import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../image/image_probe.dart';
import '../models.dart';
import '../runtime/runtime_manager.dart';
import '../settings.dart';
import '../util/format.dart';
import '../util/hardlink.dart';
import '../util/log.dart';
import '../util/notify.dart';
import '../util/power.dart';
import 'output_path.dart';

enum QueueState {
  idle('空闲'),
  running('处理中'),
  stopping('正在停止');

  const QueueState(this.label);

  final String label;
}

/// 一组可以合并到同一次推理进程调用的任务。
///
/// 合并的意义在于**模型权重只加载一次**：Real-ESRGAN 的 x4plus 权重有 33 MB，
/// 每次冷启动都要重新读入并上传到显存。把同参数的任务打包，
/// 可以把这个固定开销从「每张图一次」降到「每批一次」。
class BatchGroup {
  BatchGroup({
    required this.options,
    required this.outputExtension,
    required this.sourceVolume,
    required this.jobs,
  });

  final UpscaleOptions options;
  final String outputExtension;

  /// 源文件所在卷。同卷才能用硬链接做暂存，避免复制几十 MB 的原图。
  final String sourceVolume;

  final List<UpscaleJob> jobs;

  bool get canBatch => jobs.length > 1;

  String get executionKey => options.executionKey;
}

/// 放大任务调度与执行引擎。
///
/// 设计要点：
/// * 一次只驱动一个（可配置）推理进程，避免多进程争抢同一块 GPU 反而变慢；
/// * 任务按「执行参数 + 源卷」分组，同组任务用目录模式一次跑完；
/// * 进度不依赖推理进程的输出（自动 tile 下它几乎不输出进度），
///   而是用实测吞吐量做时间插值，配合真实回报做上限钳制。
class UpscaleEngine extends ChangeNotifier {
  UpscaleEngine({required this.runtime, required this.settings}) {
    runtime.addListener(_onRuntimeChanged);
  }

  final RuntimeManager runtime;
  final AppSettings settings;

  final List<UpscaleJob> _jobs = [];
  List<UpscaleJob> get jobs => List.unmodifiable(_jobs);

  final ValueNotifier<QueueState> state = ValueNotifier(QueueState.idle);
  final ValueNotifier<double> overallProgress = ValueNotifier(0);
  final ValueNotifier<Duration> eta = ValueNotifier(Duration.zero);
  final ValueNotifier<String?> currentFileName = ValueNotifier(null);

  /// 实时吞吐量（像素/秒），用于界面展示。
  final ValueNotifier<double> throughput = ValueNotifier(0);

  /// 正在运行的推理进程。并行度大于 1 时会有多个，全部记录以便统一中止。
  final Set<Process> _processes = {};

  var _stopRequested = false;

  /// 引擎是否已销毁。
  ///
  /// 运行循环是异步的，销毁时可能有批次正在收尾；那些回调绝不能再触碰
  /// 已经被 dispose 的 [ValueNotifier]，否则会在退出时抛出异常。
  var _disposed = false;

  /// 中止代数。每次「停止」或取消运行中的任务都会自增。
  ///
  /// 用递增的代数而不是布尔标志，是因为布尔标志在两种情况下会漏掉信号：
  /// 并行度大于 1 时，先结束的批次会把标志清掉，导致其它批次继续跑；
  /// 而在两个批次之间的空隙里置位，又会被下一个批次的初始化覆盖掉。
  int _abortGeneration = 0;

  Timer? _ticker;
  int _idCounter = 0;

  /// 累计启动的推理进程数。
  ///
  /// 这个数字直接反映了批次合并的效果：同样处理 N 张图，
  /// 数字越小说明模型的重复加载越少。也用于端到端测试验证合并逻辑。
  int get processLaunchCount => _processLaunchCount;
  int _processLaunchCount = 0;

  /// 批次内的实时估算上下文。
  _GroupProgress? _groupProgress;

  bool get isRunning => state.value == QueueState.running || state.value == QueueState.stopping;

  int get pendingCount => _jobs.where((j) => !j.status.value.isTerminal).length;

  int get completedCount => _jobs.where((j) => j.status.value == JobStatus.done).length;

  int get failedCount => _jobs.where((j) => j.status.value == JobStatus.failed).length;

  bool get hasWork => _jobs.any((j) => j.status.value == JobStatus.queued);

  // ── 队列编辑 ────────────────────────────────────────────────────────────

  UpscaleJob createJob({
    required String inputPath,
    required ImageInfo sourceInfo,
    required UpscaleOptions options,
  }) {
    return UpscaleJob(
      id: 'job_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}',
      inputPath: inputPath,
      sourceInfo: sourceInfo,
      options: options,
    );
  }

  void addJobs(Iterable<UpscaleJob> incoming) {
    var added = 0;
    for (final job in incoming) {
      // 同一路径 + 同一参数不重复入队。
      final duplicate = _jobs.any((existing) =>
          existing.inputPath.toLowerCase() == job.inputPath.toLowerCase() &&
          !existing.status.value.isTerminal &&
          existing.options.executionKey == job.options.executionKey);
      if (duplicate) continue;
      _jobs.add(job);
      added++;
    }
    if (added > 0) {
      Log.i('Engine', '加入 $added 个任务，当前队列 ${_jobs.length} 项');
      _recomputeOverall();
      notifyListeners();
    }
  }

  /// 把最新的参数应用到所有**尚未开始**的任务。
  ///
  /// 参数在界面上是全局的，用户改完模型或倍率后，理应作用于整个待办队列；
  /// 已经在处理或已完成的任务保持它们当初的参数，避免结果前后不一致。
  void applyOptionsToPending(UpscaleOptions options) {
    var changed = 0;
    for (final job in _jobs) {
      if (job.status.value != JobStatus.queued) continue;
      // 逐字段比较，而不是只比 executionKey：executionKey 只覆盖影响推理
      // 进程的参数，输出侧的子文件夹名、覆盖策略等如果变了，也必须同步下去。
      if (job.options.sameAs(options)) continue;
      job.options = options;
      changed++;
    }
    if (changed > 0) {
      _recomputeOverall();
      notifyListeners();
      Log.d('Engine', '参数已同步到 $changed 个待处理任务');
    }
  }

  /// 依据历史实测吞吐量估算处理某个任务需要多久。
  ///
  /// 返回 `null` 表示还没有可用的实测数据——此时界面应当诚实地说「未知」，
  /// 而不是给一个可能相差十倍的数字。
  Duration? estimateDuration(UpscaleOptions options, int pixels) {
    final pps = settings.throughputFor(_throughputKey(options));
    if (pps == null || pps <= 0 || pixels <= 0) return null;
    return Duration(milliseconds: (pixels / pps * 1000).round());
  }

  void removeJob(UpscaleJob job) {
    if (job.status.value == JobStatus.running) {
      _abortGeneration++;
      _killRunningProcesses();
    }
    _jobs.remove(job);
    job.dispose();
    _recomputeOverall();
    notifyListeners();
  }

  void clearFinished() {
    final finished = _jobs.where((j) => j.status.value.isTerminal).toList();
    for (final job in finished) {
      _jobs.remove(job);
      job.dispose();
    }
    if (finished.isNotEmpty) {
      _recomputeOverall();
      notifyListeners();
    }
  }

  void clearAll() {
    if (isRunning) stop();
    for (final job in _jobs) {
      job.dispose();
    }
    _jobs.clear();
    _recomputeOverall();
    notifyListeners();
  }

  /// 重试失败与已取消的任务。
  void retryFailed() {
    var count = 0;
    for (final job in _jobs) {
      final status = job.status.value;
      if (status == JobStatus.failed || status == JobStatus.canceled) {
        if (_requeue(job)) count++;
      }
    }
    if (count > 0) {
      Log.i('Engine', '重新排队 $count 个任务');
      _recomputeOverall();
      notifyListeners();
    }
  }

  /// 重试单个失败/已取消的任务。
  ///
  /// 右侧菜单的「重新排队」走这里而不是直接改 [UpscaleJob] 的字段，
  /// 保证清理、进度归位与整体进度重算都走同一套逻辑。
  bool retryJob(UpscaleJob job) {
    if (_requeue(job)) {
      _recomputeOverall();
      notifyListeners();
      return true;
    }
    return false;
  }

  bool _requeue(UpscaleJob job) {
    final status = job.status.value;
    if (status != JobStatus.failed && status != JobStatus.canceled) return false;
    job.status.value = JobStatus.queued;
    job.progress.value = 0;
    job.errorMessage.value = null;
    job.outputPath.value = null;
    return true;
  }

  // ── 运行控制 ────────────────────────────────────────────────────────────

  /// 开始处理队列中所有待办任务。已开始运行时调用无副作用。
  void start() {
    if (isRunning) return;
    if (!runtime.isReady) {
      Log.w('Engine', '运行时未就绪，无法开始');
      return;
    }
    if (!hasWork) return;

    _stopRequested = false;
    // 每次开始都是一次全新的运行，之前的中止信号不再适用。
    state.value = QueueState.running;
    if (settings.preventSleep) PowerGuard.acquire();

    _ticker ??= Timer.periodic(const Duration(milliseconds: 120), (_) => _onTick());
    unawaited(_runLoop().whenComplete(() {
      _ticker?.cancel();
      _ticker = null;
      _processes.clear();
      _groupProgress = null;
      PowerGuard.release();
      if (_disposed) return;
      state.value = QueueState.idle;
      currentFileName.value = null;
      throughput.value = 0;
      eta.value = Duration.zero;
      _recomputeOverall();
      notifyListeners();
      Log.i('Engine', '队列处理结束：成功 $completedCount，失败 $failedCount');
      _announceCompletion();
    }));
    notifyListeners();
  }

  /// 停止当前批次。**未处理的任务会回到排队状态**，因此再次点击开始即可续跑。
  void stop() {
    if (!isRunning) return;
    _stopRequested = true;
    _abortGeneration++;
    state.value = QueueState.stopping;
    _killRunningProcesses();
    notifyListeners();
  }

  /// 取消单个任务。
  ///
  /// 排队中的任务直接标记为已取消；正在处理的任务会中止当前批次，
  /// 同批次里尚未开始的任务回到队列，下次开始时会重新处理。
  void cancelJob(UpscaleJob job) {
    if (job.status.value.isTerminal) return;
    if (job.status.value == JobStatus.running) {
      _abortGeneration++;
      _killRunningProcesses();
    }
    // 先落状态再中止：批次回滚时只会把状态仍为 running 的任务放回队列，
    // 因此这个任务不会被「复活」。
    job.status.value = JobStatus.canceled;
    job.progress.value = 0;
    Log.i('Engine', '已取消任务 [${job.inputName}]');
    _recomputeOverall();
    notifyListeners();
  }

  /// 调整队列顺序。处理顺序由队列顺序决定，因此这直接控制先做哪些图。
  ///
  /// [newIndex] 是**已针对「移除旧位置」修正过**的目标下标，
  /// 也就是 `ReorderableListView.onReorderItem` 的约定——
  /// 用的是老接口 `onReorder` 的话需要自己减一，这里不要再补偿一次。
  void reorderJob(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _jobs.length) return;
    if (newIndex < 0 || newIndex >= _jobs.length || newIndex == oldIndex) return;

    final job = _jobs.removeAt(oldIndex);
    _jobs.insert(newIndex, job);
    notifyListeners();
  }

  void _killRunningProcesses() {
    for (final process in _processes.toList()) {
      try {
        process.kill();
      } on Object catch (error) {
        Log.w('Engine', '中止推理进程失败：$error');
      }
    }
  }

  Future<void> _runLoop() async {
    final workers = <Future<void>>[];
    for (var i = 0; i < settings.concurrency; i++) {
      workers.add(_workerLoop());
    }
    await Future.wait(workers);
  }

  Future<void> _workerLoop() async {
    while (!_stopRequested) {
      final group = _claimNextGroup();
      if (group == null) return;
      await _runGroup(group);
    }
  }

  /// 选取并**同步占用**下一个批次。
  ///
  /// 这里在同一个事件循环内把任务状态改为 running，因此多个 worker
  /// 不会抢到同一批任务——Dart 单线程模型天然保证了这一点。
  BatchGroup? _claimNextGroup() {
    final pending = _jobs.where((j) => j.status.value == JobStatus.queued).toList();
    if (pending.isEmpty) return null;

    final buckets = <String, List<UpscaleJob>>{};
    for (final job in pending) {
      final ext = job.options.format.extensionFor(job.sourceInfo.format);
      final key = '${job.options.executionKey}|${job.volume}|$ext';
      buckets.putIfAbsent(key, () => []).add(job);
    }

    // 选择「包含队首任务」的那个批次，而不是最大的那个。
    //
    // 因为分组是全局的，两种选法产生的批次数完全一样（模型加载次数相同），
    // 但按队首选择能尊重用户的排序——这是列表类界面最基本的预期。
    final first = pending.first;
    final firstKey = '${first.options.executionKey}|${first.volume}'
        '|${first.options.format.extensionFor(first.sourceInfo.format)}';
    final best = buckets[firstKey]!;
    final grouped = best.take(_batchLimit(best.length)).toList();

    for (final job in grouped) {
      job.status.value = JobStatus.running;
      job.progress.value = 0;
      job.startedAt = DateTime.now();
      job.finishedAt = null;
      job.errorMessage.value = null;
    }

    return BatchGroup(
      options: first.options,
      outputExtension: first.options.format.extensionFor(first.sourceInfo.format),
      sourceVolume: first.volume,
      jobs: grouped,
    );
  }

  /// 单个进程一次处理过多文件并不划算：中途出错的代价会放大，
  /// 进度反馈也会变得很粗。分批上限让两者取得平衡。
  int _batchLimit(int available) => math.min(available, 64);

  // ── 批次执行 ────────────────────────────────────────────────────────────

  Future<void> _runGroup(BatchGroup group) async {
    // 记录本次执行的代数；期间任何中止操作都会让它失配。
    final generation = _abortGeneration;

    // 预先解析所有输出路径，保证同一批次内不会互相覆盖。
    final now = DateTime.now();
    final reserved = <String>{};
    final destinations = <UpscaleJob, String>{};
    for (final job in group.jobs) {
      final path = OutputResolver.resolve(job, now: now, reserved: reserved);
      reserved.add(path.toLowerCase());
      destinations[job] = path;
      job.outputPath.value = path;
    }

    _groupProgress = _GroupProgress(
      jobs: group.jobs,
      throughput: _seedThroughput(group),
    );

    try {
      if (group.canBatch) {
        await _executeBatch(group, destinations, generation);
      } else {
        await _executeSingle(group.jobs.single, destinations[group.jobs.single]!, generation);
      }
    } on _AbortedBatch {
      // 用户主动停止：未完成的任务回到排队状态，方便续跑。
      for (final job in group.jobs) {
        if (job.status.value == JobStatus.running) {
          _restoreToQueued(job);
        }
      }
    } on Object catch (error, stack) {
      Log.e('Engine', '批次执行异常', error, stack);
      for (final job in group.jobs) {
        if (job.status.value == JobStatus.running) {
          _failJob(job, '$error');
        }
      }
    } finally {
      _groupProgress = null;
      _recomputeOverall();
    }
  }

  void _restoreToQueued(UpscaleJob job) {
    // 任务已被用户从队列中移除时不必恢复。
    if (!_jobs.contains(job)) return;
    job.status.value = JobStatus.queued;
    job.progress.value = 0;
    job.startedAt = null;
  }

  Future<void> _executeSingle(UpscaleJob job, String destination, int generation) async {
    if (!File(job.inputPath).existsSync()) {
      _failJob(job, '源文件已不存在');
      return;
    }

    final outputDir = Directory(p.dirname(destination));
    if (!outputDir.existsSync()) {
      await outputDir.create(recursive: true);
    }

    final args = _buildArgs(
      input: job.inputPath,
      output: destination,
      options: job.options,
      format: job.options.format.extensionFor(job.sourceInfo.format),
    );

    final exitCode = await _spawn(args, onLine: (line) => _consumeLine(line, job));
    if (_abortGeneration != generation) throw const _AbortedBatch();

    if (exitCode != 0) {
      _failJob(job, _describeExitCode(exitCode));
      return;
    }
    if (!File(destination).existsSync()) {
      _failJob(job, '推理进程已退出但没有生成输出文件');
      return;
    }

    _completeJob(job);
  }

  Future<void> _executeBatch(
    BatchGroup group,
    Map<UpscaleJob, String> destinations,
    int generation,
  ) async {
    final batchId = 'batch_${DateTime.now().microsecondsSinceEpoch}';
    final root = Directory(p.join(AppPaths.cache.path, 'batch', batchId));
    final inDir = Directory(p.join(root.path, 'in'));
    final outDir = Directory(p.join(root.path, 'out'));

    final staged = <int, UpscaleJob>{};
    try {
      await inDir.create(recursive: true);
      await outDir.create(recursive: true);

      // 暂存输入。优先硬链接——NTFS 上零拷贝，即使源图有 100 MB 也瞬间完成。
      var linked = 0;
      for (var i = 0; i < group.jobs.length; i++) {
        final job = group.jobs[i];
        final source = File(job.inputPath);
        if (!source.existsSync()) {
          _failJob(job, '源文件已不存在');
          continue;
        }
        final ext = p.extension(job.inputPath).toLowerCase();
        final target = p.join(inDir.path, '$i$ext');
        if (HardLink.create(target, job.inputPath)) {
          linked++;
        } else {
          await source.copy(target);
        }
        staged[i] = job;
      }

      Log.d('Engine', '批次 $batchId：${staged.length} 个文件（硬链接 $linked 个）');

      if (staged.isEmpty) throw const _AbortedBatch();

      final args = _buildArgs(
        input: inDir.path,
        output: outDir.path,
        options: group.options,
        format: group.outputExtension,
      );

      final exitCode = await _spawn(args, onLine: _consumeBatchLine);
      if (_abortGeneration != generation) throw const _AbortedBatch();

      if (exitCode != 0) {
        final message = _describeExitCode(exitCode);
        for (final job in group.jobs) {
          if (job.status.value == JobStatus.running) _failJob(job, message);
        }
        return;
      }

      // 把暂存目录里的产物搬回真正的目标位置。
      var moved = 0;
      for (final entry in staged.entries) {
        final job = entry.value;
        if (job.status.value != JobStatus.running) continue;

        final produced = File(p.join(outDir.path, '${entry.key}.${group.outputExtension}'));
        if (!produced.existsSync()) {
          _failJob(job, '推理进程未生成该文件的输出');
          continue;
        }
        try {
          await _relocate(produced, destinations[job]!);
          moved++;
          _completeJob(job);
        } on Object catch (error) {
          _failJob(job, '写入输出文件失败：$error');
        }
      }
      Log.i('Engine', '批次 $batchId 完成，已写出 $moved 个文件');
    } finally {
      // 暂存目录必须清理，否则缓存会随使用无限增长。
      unawaited(_deleteQuietly(root));
    }
  }

  /// 跨卷移动文件：先尝试原子重命名，失败则退化为复制 + 删除。
  static Future<void> _relocate(File source, String destination) async {
    final target = File(destination);
    await target.parent.create(recursive: true);
    if (target.existsSync()) await target.delete();
    try {
      await source.rename(destination);
    } on Object {
      await source.copy(destination);
      await source.delete();
    }
  }

  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on Object catch (error) {
      Log.w('Engine', '清理暂存目录失败：$error');
    }
  }

  // ── 进程 ────────────────────────────────────────────────────────────────

  List<String> _buildArgs({
    required String input,
    required String output,
    required UpscaleOptions options,
    required String format,
  }) {
    final args = <String>[
      '-i', input,
      '-o', output,
      '-m', runtime.modelsDir,
      '-n', options.modelId,
      '-s', '${options.scale}',
      '-f', format,
    ];
    if (options.tileSize > 0) {
      args.addAll(['-t', '${options.tileSize}']);
    }
    if (options.gpuId >= 0) {
      args.addAll(['-g', '${options.gpuId}']);
    }
    if (options.tta) args.add('-x');
    // 打开详细输出：这样即使自动 tile 模式不打印进度，
    // 也能从设备行中解析出 GPU 信息并回填到界面。
    args.add('-v');
    return args;
  }

  Future<int> _spawn(List<String> args, {required void Function(String) onLine}) async {
    _processLaunchCount++;
    Log.d('Engine', '启动推理：${p.basename(runtime.binaryPath)} ${args.join(' ')}');

    // 以运行时目录为工作目录，确保 vcomp140.dll 等依赖能被加载。
    final process = await Process.start(
      runtime.binaryPath,
      args,
      workingDirectory: AppPaths.runtime.path,
      runInShell: false,
    );
    _processes.add(process);

    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(onLine)
        .asFuture<void>();

    // stdout 也需要消费，否则管道写满会导致子进程阻塞。
    final stdoutDone = process.stdout.drain<void>();

    final exitCode = await process.exitCode;
    await Future.wait([stderrDone, stdoutDone]);
    _processes.remove(process);
    return exitCode;
  }

  /// 解析推理进程的输出行。
  ///
  /// 已知的行格式：
  /// * `  12.34%`                        —— 分块进度（仅在显式指定 tile 时出现）
  /// * `[0 Intel(R) UHD Graphics] ...`   —— Vulkan 设备枚举
  /// * `in.png -> out.png done`          —— 单个文件完成
  static final _percentPattern = RegExp(r'^\s*(\d+(?:\.\d+)?)%\s*$');
  static final _donePattern = RegExp(r'[\\/](\d+)\.[A-Za-z0-9]+\s+->\s+.+?\s+done');

  /// 记录推理进程输出的非进度行。这些通常是错误信息，
  /// 在「进程正常退出但没有产物」这类静默失败里是唯一的线索。
  void _noteUnparsed(String line) {
    Log.d('ncnn', line);
  }

  void _consumeLine(String line, UpscaleJob job) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    final percent = _percentPattern.firstMatch(trimmed);
    if (percent != null) {
      final value = (double.tryParse(percent.group(1)!) ?? 0) / 100;
      _groupProgress?.reportFraction(job, value);
      job.progress.value = value;
      return;
    }

    if (RuntimeManager.gpuDeviceLinePattern.hasMatch(trimmed)) {
      _ingestDeviceLine(trimmed);
      return;
    }

    if (trimmed.contains('done')) {
      _completeJob(job);
      return;
    }

    _noteUnparsed(trimmed);
  }

  void _consumeBatchLine(String line) {
    final progress = _groupProgress;
    if (progress == null) return;

    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    final percent = _percentPattern.firstMatch(trimmed);
    if (percent != null) {
      final value = (double.tryParse(percent.group(1)!) ?? 0) / 100;
      final job = progress.currentJob;
      if (job != null) {
        progress.reportFraction(job, value);
        job.progress.value = value;
      }
      return;
    }

    if (RuntimeManager.gpuDeviceLinePattern.hasMatch(trimmed)) {
      _ingestDeviceLine(trimmed);
      return;
    }

    final done = _donePattern.firstMatch(trimmed);
    if (done != null) {
      final index = int.tryParse(done.group(1)!);
      if (index != null) progress.markCompleted(index);
      return;
    }

    _noteUnparsed(trimmed);
  }

  /// 把从推理进程顺带发现的 GPU 列表回填给运行时管理器，
  /// 这样用户不必手动点「检测 GPU」。
  final List<String> _deviceLines = [];
  Timer? _deviceFlush;

  void _ingestDeviceLine(String line) {
    _deviceLines.add(line);
    // 设备信息是连续的多行输出，攒一小段时间后一次性解析。
    _deviceFlush?.cancel();
    _deviceFlush = Timer(const Duration(milliseconds: 250), () {
      final devices = RuntimeManager.parseGpuDevices(_deviceLines.join('\n'));
      _deviceLines.clear();
      if (devices.isNotEmpty && !listEquals(devices, runtime.gpus.value)) {
        runtime.gpus.value = devices;
        Log.i('Engine', '已从推理进程识别到 ${devices.length} 个 Vulkan 设备');
      }
    });
  }

  static String _describeExitCode(int code) {
    return switch (code) {
      0 => '正常退出',
      -1 || 4294967295 => '推理进程被中止',
      1 => '推理失败：无法读取输入文件或显存不足（可尝试调小分块大小）',
      2 => '推理失败：不支持的图像格式',
      _ => '推理进程异常退出（代码 $code）',
    };
  }

  void _completeJob(UpscaleJob job) {
    if (_disposed) return;
    if (job.status.value == JobStatus.done) return;
    job.finishedAt = DateTime.now();
    job.progress.value = 1;
    job.status.value = JobStatus.done;

    final elapsed = job.finishedAt!.difference(job.startedAt ?? job.finishedAt!);
    job.elapsed.value = elapsed;

    // 记录实测吞吐，供后续任务估算剩余时间。
    final seconds = elapsed.inMilliseconds / 1000;
    if (seconds > 0.05 && job.pixelCount > 0) {
      final pps = job.pixelCount / seconds;
      settings.recordThroughput(_throughputKey(job.options), pps);
      _groupProgress?.observe(pps);
      throughput.value = pps;
    }
    notifyListeners();
  }

  void _failJob(UpscaleJob job, String message) {
    if (_disposed) return;
    job.status.value = JobStatus.failed;
    job.errorMessage.value = message;
    job.finishedAt = DateTime.now();
    Log.w('Engine', '任务失败 [${job.inputName}]：$message');
    notifyListeners();
  }

  String _throughputKey(UpscaleOptions options) =>
      '${options.modelId}|${options.scale}|${options.gpuId}';

  double _seedThroughput(BatchGroup group) {
    final recorded = settings.throughputFor(_throughputKey(group.options));
    if (recorded != null && recorded > 0) return recorded;

    // 首次运行时的保守估计。真实值会在第一个文件完成后立刻替换掉它，
    // 因此这只影响应用生命周期内第一批任务的剩余时间显示。
    final model = findModel(group.options.modelId);
    final weight = model?.costWeight ?? 1.0;
    final scalePenalty = math.pow(group.options.scale / 4.0, 2).toDouble();
    final ttaPenalty = group.options.tta ? 8.0 : 1.0;
    return 1.2e6 / (weight * scalePenalty * ttaPenalty);
  }

  // ── 进度插值 ────────────────────────────────────────────────────────────

  void _onTick() {
    final group = _groupProgress;
    if (group == null) return;
    group.tick();
    _recomputeOverall();
  }

  void _recomputeOverall() {
    // 批次收尾可能在引擎销毁之后才跑到，这里必须挡住。
    if (_disposed) return;
    if (_jobs.isEmpty) {
      overallProgress.value = 0;
      eta.value = Duration.zero;
      return;
    }
    var sum = 0.0;
    for (final job in _jobs) {
      sum += job.status.value == JobStatus.done ? 1.0 : job.progress.value;
    }
    overallProgress.value = sum / _jobs.length;

    final group = _groupProgress;
    if (group != null) {
      eta.value = group.estimateRemaining();
      final job = group.currentJob;
      currentFileName.value = job?.inputName;
    }
  }

  /// 一轮处理结束后的提醒。
  ///
  /// 只有确实产出了结果才提醒——用户主动停止、或者队列本来就空，
  /// 都不该弹提示音打扰。
  void _announceCompletion() {
    final produced = _jobs.where((j) => j.status.value == JobStatus.done).length;
    if (produced == 0) return;

    if (settings.playSoundWhenDone) Notify.beep();
    if (settings.revealWhenDone) {
      final dir = _commonOutputDirectory();
      if (dir != null) unawaited(openDirectory(dir));
    }
  }

  /// 找出多数产物的所在目录，用于「完成后打开输出目录」。
  String? _commonOutputDirectory() {
    final dirs = <String, int>{};
    for (final job in _jobs) {
      if (job.status.value != JobStatus.done) continue;
      final path = job.outputPath.value;
      if (path == null) continue;
      final dir = File(path).parent.path;
      dirs[dir] = (dirs[dir] ?? 0) + 1;
    }
    if (dirs.isEmpty) return null;
    return dirs.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  /// 在资源管理器中打开目录。核心层不依赖 UI，因此直接调用系统命令。
  static Future<void> openDirectory(String path) async {
    if (!Platform.isWindows) return;
    try {
      await Process.run('explorer.exe', [p.normalize(path)]);
    } on Object catch (error) {
      Log.w('Engine', '打开输出目录失败：$error');
    }
  }

  void _onRuntimeChanged() {
    // 运行时安装完成后，之前因缺少引擎而无法开始的任务可以继续。
    if (runtime.isReady) notifyListeners();
  }

  @override
  void dispose() {
    // 先立起墓碑再动手：正在收尾的批次回调会读到这个标记并提前退出。
    _disposed = true;
    _stopRequested = true;
    runtime.removeListener(_onRuntimeChanged);
    _ticker?.cancel();
    _deviceFlush?.cancel();
    _killRunningProcesses();
    PowerGuard.release();
    state.dispose();
    overallProgress.dispose();
    eta.dispose();
    currentFileName.dispose();
    throughput.dispose();
    for (final job in _jobs) {
      job.dispose();
    }
    super.dispose();
  }
}

/// 批次内进度与剩余时间的估算器。
///
/// 推理进程在「自动分块」模式下几乎不输出进度（它只在分块边界打印百分比），
/// 因此这里用实测吞吐量做时间插值：既保证进度条始终平滑推进，
/// 又用真实回报值作为下限钳制，不会出现「先冲到 90% 再卡住」的假象。
class _GroupProgress {
  _GroupProgress({required this.jobs, required double throughput})
      : _pixelsPerSecond = throughput;

  final List<UpscaleJob> jobs;
  double _pixelsPerSecond;
  bool _measured = false;

  int _currentIndex = 0;
  double _reportedFraction = 0;
  DateTime _currentStartedAt = DateTime.now();

  int _totalPixels = 0;
  int _donePixels = 0;

  UpscaleJob? get currentJob => _currentIndex < jobs.length ? jobs[_currentIndex] : null;

  bool get isMeasured => _measured;

  void observe(double pixelsPerSecond) {
    if (pixelsPerSecond <= 0) return;
    _measured = true;
    _pixelsPerSecond = pixelsPerSecond;
  }

  void reportFraction(UpscaleJob job, double value) {
    if (job != currentJob) {
      // 真实回报指向了下一个文件，说明上一个已经结束但没打印完成行。
      final index = jobs.indexOf(job);
      if (index > _currentIndex) _advanceTo(index);
    }
    _reportedFraction = math.max(_reportedFraction, Fmt.clamp01(value));
    job.progress.value = math.max(job.progress.value, _reportedFraction);
  }

  void markCompleted(int index) {
    final job = jobs[index];
    job.progress.value = 1;
    if (index >= _currentIndex) _advanceTo(index + 1);
  }

  void _advanceTo(int index) {
    _currentIndex = index;
    _reportedFraction = 0;
    _currentStartedAt = DateTime.now();
  }

  /// 每次心跳推进一次进度。
  void tick() {
    final job = currentJob;
    if (job == null) return;

    final elapsedSeconds = DateTime.now().difference(_currentStartedAt).inMilliseconds / 1000;
    if (job.pixelCount <= 0 || _pixelsPerSecond <= 0) return;

    final estimatedPixels = elapsedSeconds * _pixelsPerSecond;
    final estimatedFraction = estimatedPixels / job.pixelCount;

    // 时间估算只用于「填补真实回报之间的空隙」，永远不覆盖真实值，
    // 并且封顶在 97%，避免进度条先跑满再等待。
    final shown = math.min(math.max(estimatedFraction, _reportedFraction), 0.97);
    if (shown > job.progress.value) {
      job.progress.value = shown;
    }
  }

  Duration estimateRemaining() {
    if (_pixelsPerSecond <= 0) return Duration.zero;
    _totalPixels = 0;
    _donePixels = 0;
    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      _totalPixels += job.pixelCount;
      if (i < _currentIndex) {
        _donePixels += job.pixelCount;
      } else if (i == _currentIndex) {
        _donePixels += (job.pixelCount * job.progress.value).round();
      }
    }
    final remaining = _totalPixels - _donePixels;
    if (remaining <= 0) return Duration.zero;
    final seconds = remaining / _pixelsPerSecond;
    // 超过一天的估算没有意义，直接隐藏。
    if (seconds > 86400) return Duration.zero;
    return Duration(seconds: seconds.round());
  }
}

class _AbortedBatch implements Exception {
  const _AbortedBatch();
}
