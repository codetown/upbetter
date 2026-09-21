import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'image/image_probe.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 模型目录
// ─────────────────────────────────────────────────────────────────────────────

enum ModelCategory {
  photo('照片写实', '适合真实照片、风景、人像，细节重建能力最强'),
  anime('动漫插画', '针对二次元线稿与平涂上色优化，线条干净锐利'),
  fast('极速通用', '体积最小、速度最快，适合批量预览与视频帧');

  const ModelCategory(this.label, this.description);

  final String label;
  final String description;
}

/// 一个可用的超分模型。
///
/// [id] 即传给推理进程 `-n` 参数的模型名，如 `realesrgan-x4plus`。
@immutable
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.displayName,
    required this.category,
    required this.nativeScale,
    required this.paramFile,
    required this.binFile,
    required this.sizeBytes,
  });

  final String id;
  final String displayName;
  final ModelCategory category;

  /// 模型的原生倍率。低于它的倍率请求会先按原生倍率推理再降采样，
  /// 界面据此提示用户「这个倍率不是原生的」。
  final int nativeScale;

  final String paramFile;
  final String binFile;
  final int sizeBytes;

  /// 相对耗时权重，仅用于界面上的速度预估（1.0 = realesrgan-x4plus）。
  double get costWeight => switch (id) {
        'realesr-animevideov3' => 0.12,
        'realesrgan-x4plus-anime' => 0.35,
        _ => 1.0,
      };

  @override
  bool operator ==(Object other) => other is ModelSpec && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 内置模型清单。权重随运行时压缩包一并下载。
const List<ModelSpec> kBuiltinModels = [
  ModelSpec(
    id: 'realesrgan-x4plus',
    displayName: 'Real-ESRGAN 通用',
    category: ModelCategory.photo,
    nativeScale: 4,
    paramFile: 'realesrgan-x4plus.param',
    binFile: 'realesrgan-x4plus.bin',
    sizeBytes: 34550000,
  ),
  ModelSpec(
    id: 'realesrgan-x4plus-anime',
    displayName: 'Real-ESRGAN 动漫',
    category: ModelCategory.anime,
    nativeScale: 4,
    paramFile: 'realesrgan-x4plus-anime.param',
    binFile: 'realesrgan-x4plus-anime.bin',
    sizeBytes: 9000000,
  ),
  ModelSpec(
    id: 'realesr-animevideov3',
    displayName: 'AnimeVideo v3',
    category: ModelCategory.fast,
    nativeScale: 4,
    paramFile: 'realesr-animevideov3-x4.param',
    binFile: 'realesr-animevideov3-x4.bin',
    sizeBytes: 1300000,
  ),
];

ModelSpec? findModel(String id) {
  for (final m in kBuiltinModels) {
    if (m.id == id) return m;
  }
  return null;
}

/// 扫描模型目录，发现用户自行放入的 `.param` / `.bin` 模型对。
///
/// 这让高级用户可以直接把社区模型拖进模型目录使用，无需等待应用更新。
Future<List<ModelSpec>> discoverCustomModels(String modelsDir) async {
  final dir = Directory(modelsDir);
  if (!dir.existsSync()) return const [];

  final known = {for (final m in kBuiltinModels) m.id};
  final result = <ModelSpec>[];

  for (final entity in dir.listSync()) {
    if (entity is! File || p.extension(entity.path).toLowerCase() != '.param') continue;
    final binPath = '${p.withoutExtension(entity.path)}.bin';
    if (!File(binPath).existsSync()) continue;

    var id = p.basenameWithoutExtension(entity.path);
    // 形如 realesr-animevideov3-x2 的变体不单独暴露，交由基础模型按倍率选择。
    if (RegExp(r'-x[234]$').hasMatch(id)) continue;
    if (known.contains(id)) continue;

    result.add(ModelSpec(
      id: id,
      displayName: id,
      category: ModelCategory.photo,
      nativeScale: 4,
      paramFile: p.basename(entity.path),
      binFile: p.basename(binPath),
      sizeBytes: File(binPath).lengthSync(),
    ));
  }
  result.sort((a, b) => a.id.compareTo(b.id));
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// 输出选项
// ─────────────────────────────────────────────────────────────────────────────

enum OutputFormat {
  original('保持原格式', 'auto'),
  png('PNG（无损）', 'png'),
  jpg('JPEG（体积小）', 'jpg'),
  webp('WebP（现代化）', 'webp');

  const OutputFormat(this.label, this.flag);

  final String label;

  /// 传给推理进程 `-f` 的值。
  final String flag;

  String extensionFor(ImageFormat sourceFormat) {
    if (this == OutputFormat.original) {
      return switch (sourceFormat) {
        ImageFormat.png => 'png',
        ImageFormat.jpeg => 'jpg',
        ImageFormat.webp => 'webp',
        _ => 'png',
      };
    }
    return flag;
  }
}

enum OutputLocation {
  alongside('源文件旁边', '输出到与原图相同的目录'),
  custom('指定目录', '输出到你选择的文件夹'),
  subfolder('子文件夹', '在原图目录下创建子文件夹');

  const OutputLocation(this.label, this.description);

  final String label;
  final String description;
}

// ─────────────────────────────────────────────────────────────────────────────
// 放大参数
// ─────────────────────────────────────────────────────────────────────────────

/// 一次放大任务的全部参数。不可变，因此可以安全地跨 isolate 传递并被队列分组。
@immutable
class UpscaleOptions {
  const UpscaleOptions({
    this.modelId = 'realesrgan-x4plus',
    this.scale = 4,
    this.format = OutputFormat.original,
    this.location = OutputLocation.alongside,
    this.outputDir,
    this.subfolderName = 'upbetter',
    this.namingTemplate = '{name}_upbetter',
    this.tileSize = 0,
    this.gpuId = -1,
    this.tta = false,
    this.overwrite = false,
  });

  final String modelId;
  final int scale;
  final OutputFormat format;
  final OutputLocation location;
  final String? outputDir;
  final String subfolderName;

  /// 输出文件名模板，支持 `{name}` `{scale}` `{model}` `{date}` `{time}`。
  final String namingTemplate;

  /// 推理分块大小，0 表示由运行时自动决定（推荐）。
  final int tileSize;

  /// GPU 设备索引，-1 表示自动选择。
  final int gpuId;

  /// TTA 模式：8 倍计算量换取极微小的质量提升。
  final bool tta;

  final bool overwrite;

  UpscaleOptions copyWith({
    String? modelId,
    int? scale,
    OutputFormat? format,
    OutputLocation? location,
    String? outputDir,
    String? subfolderName,
    String? namingTemplate,
    int? tileSize,
    int? gpuId,
    bool? tta,
    bool? overwrite,
  }) {
    return UpscaleOptions(
      modelId: modelId ?? this.modelId,
      scale: scale ?? this.scale,
      format: format ?? this.format,
      location: location ?? this.location,
      outputDir: outputDir ?? this.outputDir,
      subfolderName: subfolderName ?? this.subfolderName,
      namingTemplate: namingTemplate ?? this.namingTemplate,
      tileSize: tileSize ?? this.tileSize,
      gpuId: gpuId ?? this.gpuId,
      tta: tta ?? this.tta,
      overwrite: overwrite ?? this.overwrite,
    );
  }

  /// 决定推理进程行为的参数子集。相同 [executionKey] 的任务可以合并到同一次进程调用，
  /// 从而只加载一次模型权重——这是批量处理最主要的性能优化。
  String get executionKey => '$modelId|$scale|${format.flag}|$tileSize|$gpuId|$tta';

  /// 与另一份参数是否**逐字段相等**。
  ///
  /// 用于「全局参数同步」时判断待处理任务是否真的需要更新。
  /// 不要用 `==`：这个类是设计为便宜的值对象，但它没有覆写相等性，
  /// 逐字段比较才是这里想要的语义。
  bool sameAs(UpscaleOptions other) {
    return modelId == other.modelId &&
        scale == other.scale &&
        format == other.format &&
        location == other.location &&
        outputDir == other.outputDir &&
        subfolderName == other.subfolderName &&
        namingTemplate == other.namingTemplate &&
        tileSize == other.tileSize &&
        gpuId == other.gpuId &&
        tta == other.tta &&
        overwrite == other.overwrite;
  }

  Map<String, Object?> toJson() => {
        'modelId': modelId,
        'scale': scale,
        'format': format.name,
        'location': location.name,
        'outputDir': outputDir,
        'subfolderName': subfolderName,
        'namingTemplate': namingTemplate,
        'tileSize': tileSize,
        'gpuId': gpuId,
        'tta': tta,
        'overwrite': overwrite,
      };

  static UpscaleOptions fromJson(Map<String, Object?> json) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) {
      if (name is! String) return fallback;
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    return UpscaleOptions(
      modelId: json['modelId'] as String? ?? 'realesrgan-x4plus',
      scale: (json['scale'] as num?)?.toInt().clamp(1, 8) ?? 4,
      format: pick(OutputFormat.values, json['format'], OutputFormat.original),
      location: pick(OutputLocation.values, json['location'], OutputLocation.alongside),
      outputDir: json['outputDir'] as String?,
      subfolderName: json['subfolderName'] as String? ?? 'upbetter',
      namingTemplate: json['namingTemplate'] as String? ?? '{name}_upbetter',
      tileSize: (json['tileSize'] as num?)?.toInt() ?? 0,
      gpuId: (json['gpuId'] as num?)?.toInt() ?? -1,
      tta: json['tta'] as bool? ?? false,
      overwrite: json['overwrite'] as bool? ?? false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 任务
// ─────────────────────────────────────────────────────────────────────────────

enum JobStatus {
  queued('排队中'),
  running('处理中'),
  done('已完成'),
  failed('失败'),
  canceled('已取消');

  const JobStatus(this.label);

  final String label;

  bool get isTerminal => this == done || this == failed || this == canceled;
  bool get isActive => this == running;
}

/// 队列中的单个文件。
///
/// 进度与状态存放在 [ValueNotifier] 中，因此单个任务的进度更新
/// 只会重建对应的那一行，而不会触发整个列表重建——这是长队列保持满帧的关键。
class UpscaleJob {
  UpscaleJob({
    required this.id,
    required this.inputPath,
    required this.sourceInfo,
    required this.options,
  })  : inputName = p.basename(inputPath),
        inputDir = p.dirname(inputPath),
        volume = p.rootPrefix(inputPath);

  final String id;
  final String inputPath;
  final String inputName;
  final String inputDir;

  /// 源文件所在卷（如 `D:\`）。用于把可硬链接的文件分到同一批。
  final String volume;

  final ImageInfo sourceInfo;

  /// 每个任务创建时的参数快照。用户之后修改全局参数不会影响已排队的任务。
  UpscaleOptions options;

  final status = ValueNotifier<JobStatus>(JobStatus.queued);
  final progress = ValueNotifier<double>(0);
  final outputPath = ValueNotifier<String?>(null);
  final errorMessage = ValueNotifier<String?>(null);
  final elapsed = ValueNotifier<Duration>(Duration.zero);

  DateTime? startedAt;
  DateTime? finishedAt;

  int get pixelCount => sourceInfo.pixels;

  int get outputWidth => sourceInfo.width * options.scale;

  int get outputHeight => sourceInfo.height * options.scale;

  int get outputPixels => outputWidth * outputHeight;

  /// 是否已产出一个真实存在于磁盘上的结果文件。
  ///
  /// 任务达成 `done` 状态但输出被用户手动删除时同样返回 `false`，
  /// 界面据此回退到只展示原图，而不是显示一个悬空的结果路径。
  bool get hasResult {
    final path = outputPath.value;
    return status.value == JobStatus.done &&
        path != null &&
        File(path).existsSync();
  }

  void dispose() {
    status.dispose();
    progress.dispose();
    outputPath.dispose();
    errorMessage.dispose();
    elapsed.dispose();
  }
}
