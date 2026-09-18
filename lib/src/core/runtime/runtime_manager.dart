import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../models.dart';
import '../util/log.dart';
import 'downloader.dart';

/// 推理运行时的安装状态。
enum RuntimeStage {
  checking('正在检测运行环境'),
  absent('尚未安装推理引擎'),
  downloading('正在下载推理引擎'),
  extracting('正在解压模型权重'),
  ready('就绪'),
  error('安装失败');

  const RuntimeStage(this.label);

  final String label;
}

/// 探测到的 Vulkan 设备。
@immutable
class GpuDevice {
  const GpuDevice({required this.index, required this.name});

  final int index;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is GpuDevice && other.index == index && other.name == name;

  @override
  int get hashCode => Object.hash(index, name);
}

/// 推理运行时（Real-ESRGAN ncnn Vulkan）的生命周期管理。
///
/// 负责：定位/下载/校验/解压可执行文件与模型权重，以及枚举可用的 Vulkan 设备。
class RuntimeManager extends ChangeNotifier {
  RuntimeManager();

  /// 官方发行包。固定版本号 + SHA-256 双重锁定，保证可复现。
  static const String _archivePath =
      'xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip';
  static const String _archiveUrl = 'https://github.com/$_archivePath';
  static const String _archiveSha256 =
      'abc02804e17982a3be33675e4d471e91ea374e65b70167abc09e31acb412802d';
  static const int _archiveSize = 45474481;
  static const String _binaryName = 'realesrgan-ncnn-vulkan.exe';

  /// GitHub 在国内的可达性并不稳定，首次启动又强依赖这次下载，
  /// 因此准备若干镜像作为回退。**所有来源都必须通过 SHA-256 校验**，
  /// 镜像即使被劫持也无法让应用装上被篡改的引擎。
  static const List<String> _mirrorPrefixes = [
    'https://ghproxy.net/',
    'https://gh-proxy.com/',
    'https://ghfast.top/',
  ];

  /// 每个来源的重试次数。断点续传让重试的代价很低——
  /// 已经下载的部分不会白费。
  static const int _attemptsPerSource = 2;

  /// 按优先级列出下载来源：直连优先，失败后依次尝试镜像。
  static List<String> downloadSources({String? customSource}) {
    return [
      if (customSource != null && customSource.trim().isNotEmpty) customSource.trim(),
      _archiveUrl,
      for (final prefix in _mirrorPrefixes) '$prefix$_archiveUrl',
    ];
  }

  RuntimeStage _stage = RuntimeStage.checking;
  RuntimeStage get stage => _stage;

  double _progress = 0;
  double get progress => _progress;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _receivedBytes = 0;
  int _totalBytes = _archiveSize;
  int get receivedBytes => _receivedBytes;
  int get totalBytes => _totalBytes;

  double _bytesPerSecond = 0;
  double get bytesPerSecond => _bytesPerSecond;

  CancelToken? _cancelToken;

  final ValueNotifier<List<GpuDevice>> gpus = ValueNotifier(const []);
  final ValueNotifier<List<ModelSpec>> models = ValueNotifier(const []);

  bool get isReady => _stage == RuntimeStage.ready;
  bool get isBusy => _stage == RuntimeStage.downloading || _stage == RuntimeStage.extracting;

  String get binaryPath => p.join(AppPaths.runtime.path, _binaryName);
  String get modelsDir => AppPaths.models.path;

  ModelSpec? modelById(String id) {
    for (final m in models.value) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 检查运行时是否已就绪。可在启动时调用，代价很低（仅文件系统探测）。
  Future<void> refresh() async {
    final binary = File(binaryPath);
    if (!binary.existsSync()) {
      // 便携模式：允许把 runtime 目录放在 exe 旁边直接分发。
      final portable = File(p.join(p.dirname(Platform.resolvedExecutable), 'runtime', _binaryName));
      if (portable.existsSync()) {
        AppPaths.portableRuntimeOverride = portable.parent.path;
        _setStage(RuntimeStage.ready);
        await _reloadModels();
        return;
      }
      _setStage(RuntimeStage.absent);
      return;
    }
    _setStage(RuntimeStage.ready);
    await _reloadModels();
  }

  Future<void> _reloadModels() async {
    final available = <ModelSpec>[];
    for (final spec in kBuiltinModels) {
      if (File(p.join(modelsDir, spec.binFile)).existsSync() &&
          File(p.join(modelsDir, spec.paramFile)).existsSync()) {
        available.add(spec);
      }
    }
    available.addAll(await discoverCustomModels(modelsDir));
    models.value = available;
  }

  /// 下载并安装运行时。可安全地重复调用；已下载的压缩包不会被重复下载。
  Future<void> install({bool force = false, String? customSource}) async {
    if (isBusy) return;
    _errorMessage = null;
    final token = CancelToken();
    _cancelToken = token;

    try {
      final cacheDir = Directory(p.join(AppPaths.cache.path, 'bootstrap'));
      await cacheDir.create(recursive: true);
      final archiveFile = File(p.join(cacheDir.path, 'realesrgan-ncnn-vulkan.zip'));

      if (force && archiveFile.existsSync()) {
        await archiveFile.delete();
      }

      final alreadyDownloaded = archiveFile.existsSync() &&
          await archiveFile.length() == _archiveSize &&
          await Downloader.computeSha256(archiveFile) == _archiveSha256;

      if (!alreadyDownloaded) {
        _setStage(RuntimeStage.downloading);
        _receivedBytes = 0;
        _totalBytes = _archiveSize;
        _progress = 0;
        notifyListeners();

        await _downloadWithFallback(
          archiveFile: archiveFile,
          token: token,
          sources: downloadSources(customSource: customSource),
        );
      }

      token.throwIfCanceled();
      _setStage(RuntimeStage.extracting);
      _progress = 0;
      _bytesPerSecond = 0;
      notifyListeners();

      await Isolate.run(
        () => extractArchive(
          archiveFile.path,
          AppPaths.runtime.path,
          modelsDir,
          _binaryName,
        ),
      );

      token.throwIfCanceled();
      await _reloadModels();

      if (models.value.isEmpty) {
        throw DownloadException('解压后未找到任何模型权重，安装包可能已损坏');
      }

      _setStage(RuntimeStage.ready);
      Log.i('Runtime', '推理引擎安装完成，可用模型：${models.value.map((m) => m.id).join(', ')}');
    } on DownloadCanceled {
      Log.w('Runtime', '安装被用户取消');
      _setStage(RuntimeStage.absent);
    } on Object catch (error, stack) {
      Log.e('Runtime', '安装失败', error, stack);
      _errorMessage = '$error';
      _setStage(RuntimeStage.error);
    } finally {
      _cancelToken = null;
    }
  }

  /// 依次尝试各个下载来源，每个来源重试若干次。
  ///
  /// 失败会保留 `.part` 文件，因此换源重试时已下载的部分仍然有效；
  /// 只有校验不通过（文件确实损坏）时 [Downloader] 才会把它删掉。
  Future<void> _downloadWithFallback({
    required File archiveFile,
    required CancelToken token,
    required List<String> sources,
  }) async {
    Object? lastError;

    for (final source in sources) {
      for (var attempt = 1; attempt <= _attemptsPerSource; attempt++) {
        token.throwIfCanceled();
        try {
          await Downloader.download(
            url: Uri.parse(source),
            destination: archiveFile,
            token: token,
            expectedSha256: _archiveSha256,
            expectedSize: _archiveSize,
            onProgress: (received, total, speed) {
              _receivedBytes = received;
              _totalBytes = total ?? _archiveSize;
              _bytesPerSecond = speed;
              _progress = _totalBytes <= 0 ? 0 : received / _totalBytes;
              notifyListeners();
            },
          );
          if (source != _archiveUrl) {
            Log.i('Runtime', '已通过镜像完成下载：$source');
          }
          return;
        } on DownloadCanceled {
          rethrow;
        } on Object catch (error) {
          lastError = error;
          Log.w('Runtime', '下载失败（$source 第 $attempt 次）：$error');
          if (attempt < _attemptsPerSource) {
            // 短暂退避，给瞬时故障一点恢复时间。
            await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
          }
        }
      }
    }

    throw DownloadException(
      '无法下载推理引擎。请检查网络能否访问 GitHub，或设置系统代理后重试。\n'
      '最后一次错误：$lastError',
    );
  }

  void cancelInstall() => _cancelToken?.cancel();

  /// 枚举 Vulkan 设备。
  ///
  /// ncnn 只在真正执行推理时才会枚举设备，因此这里用一个 1×1 的
  /// PNG 配合最快的模型做一次极短的探测运行。
  Future<void> detectGpus() async {
    if (!isReady) return;
    final probe = File(p.join(AppPaths.cache.path, 'gpu_probe.png'));
    try {
      await probe.parent.create(recursive: true);
      await probe.writeAsBytes(_onePixelPng, flush: true);

      final result = await Process.run(
        binaryPath,
        [
          '-i', probe.path,
          '-o', '${probe.path}.out.png',
          '-n', 'realesr-animevideov3',
          '-s', '2',
          '-m', modelsDir,
          '-v',
        ],
        workingDirectory: AppPaths.runtime.path,
        stdoutEncoding: null,
        stderrEncoding: null,
      );

      final detected = parseGpuDevices(
        utf8.decode(result.stderr as List<int>, allowMalformed: true),
      );
      if (detected.isNotEmpty) {
        gpus.value = detected;
        Log.i('Runtime', '检测到 ${detected.length} 个 Vulkan 设备：'
            '${detected.map((g) => '${g.index}:${g.name}').join(', ')}');
      }
    } on Object catch (error) {
      Log.w('Runtime', 'GPU 探测失败：$error');
    } finally {
      for (final path in [probe.path, '${probe.path}.out.png']) {
        final f = File(path);
        if (f.existsSync()) {
          try {
            await f.delete();
          } on Object {
            // ignore
          }
        }
      }
    }
  }

  /// 解析 ncnn 打印的设备行，例如：
  /// `[0 Intel(R) UHD Graphics]  queueC=0[1]  queueG=0[1]`
  static List<GpuDevice> parseGpuDevices(String stderrText) {
    final pattern = RegExp(r'^\[(\d+)\s+(.+?)\]\s');
    final seen = <int>{};
    final result = <GpuDevice>[];
    for (final line in const LineSplitter().convert(stderrText)) {
      final match = pattern.firstMatch(line.trim());
      if (match == null) continue;
      final index = int.tryParse(match.group(1)!);
      if (index == null || !seen.add(index)) continue;
      result.add(GpuDevice(index: index, name: match.group(2)!.trim()));
    }
    result.sort((a, b) => a.index.compareTo(b.index));
    return result;
  }

  void _setStage(RuntimeStage stage) {
    _stage = stage;
    if (stage == RuntimeStage.ready || stage == RuntimeStage.absent) {
      _progress = stage == RuntimeStage.ready ? 1 : 0;
    }
    notifyListeners();
  }
}

/// 解压官方发行包。
///
/// 只提取真正需要的东西——可执行文件、它依赖的动态库，以及 `models/` 下的权重。
/// 发行包里还带着示例图片和一段演示视频，对用户毫无用处，直接跳过。
///
/// 该方法设计为可在独立 isolate 中调用：签名只依赖字符串，不捕获任何状态。
/// 45 MB 的解压如果放在主 isolate 会明显卡住界面。
void extractArchive(String zipPath, String runtimeDir, String modelsDir, String binaryName) {
  final bytes = File(zipPath).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);

  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = entry.name.replaceAll('\\', '/');
    final base = p.basename(name);

    final isModel = name.contains('models/');
    final isTopLevelRuntime = !name.contains('/') &&
        (base.endsWith('.exe') || base.endsWith('.dll'));
    if (!isModel && !isTopLevelRuntime) continue;

    final data = entry.readBytes();
    if (data == null) continue;

    final target = File(p.join(isModel ? modelsDir : runtimeDir, base));
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(data, flush: false);
  }

  if (!File(p.join(runtimeDir, binaryName)).existsSync()) {
    throw DownloadException('安装包中缺少可执行文件 $binaryName');
  }
}

/// 最小的合法 PNG（1×1 透明像素），用于 GPU 探测。
final List<int> _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
