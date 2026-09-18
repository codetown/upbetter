import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/models.dart';
import '../../core/runtime/runtime_manager.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../widgets/primitives.dart';

/// 高级选项：只在需要压榨性能或排查问题时才用得到。
class AdvancedSettingsSection extends StatelessWidget {
  const AdvancedSettingsSection({
    super.key,
    required this.options,
    required this.gpus,
    required this.onChanged,
  });

  final UpscaleOptions options;
  final List<GpuDevice> gpus;
  final ValueChanged<UpscaleOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('计算设备'),
        _GpuSelector(options: options, gpus: gpus, onChanged: onChanged),
        const SizedBox(height: Gap.xl),

        const SectionLabel('显存分块'),
        _TileSelector(options: options, onChanged: onChanged),
        const SizedBox(height: Gap.sm),
        Text(
          options.tileSize == 0
              ? '由引擎自动选择能装进显存的最大分块，速度最快。'
              : '固定分块会降低显存占用，但速度变慢。遇到显存不足时再调小。',
          style: text.labelSmall?.copyWith(color: t.textTertiary, height: 1.4),
        ),
        const SizedBox(height: Gap.xl),

        SwitchRow(
          label: 'TTA 增强模式',
          detail: options.tta ? '8 倍计算量，收益极小' : '关闭（推荐）',
          value: options.tta,
          onChanged: (v) => onChanged(options.copyWith(tta: v)),
        ),
        if (options.tta)
          Container(
            margin: const EdgeInsets.only(top: Gap.sm),
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: t.warning.withValues(alpha: 0.1),
              borderRadius: Radii.allSm,
              border: Border.all(color: t.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Symbols.warning, size: 15, color: t.warning),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    'TTA 会让处理时间增加到约 8 倍，画质提升通常在肉眼不可见的级别。',
                    style: text.labelSmall?.copyWith(color: t.textSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: Gap.xl),

        const _RuntimeSection(),
      ],
    );
  }
}

class _GpuSelector extends StatelessWidget {
  const _GpuSelector({
    required this.options,
    required this.gpus,
    required this.onChanged,
  });

  final UpscaleOptions options;
  final List<GpuDevice> gpus;
  final ValueChanged<UpscaleOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final runtime = AppScope.of(context).runtime;

    if (gpus.isEmpty) {
      return Panel(
        padding: const EdgeInsets.all(Gap.md),
        color: t.surfaceSunken,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.memory, size: 15, color: t.textTertiary),
                const SizedBox(width: Gap.sm),
                Expanded(child: Text('尚未识别到设备', style: text.bodySmall)),
              ],
            ),
            const SizedBox(height: Gap.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: runtime.detectGpus,
                child: const Text('检测 GPU'),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final gpu in gpus) ...[
          SelectableCard(
            selected: options.gpuId == gpu.index,
            padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
            onTap: () => onChanged(options.copyWith(gpuId: gpu.index)),
            child: Row(
              children: [
                Icon(
                  Symbols.memory,
                  size: 16,
                  color: options.gpuId == gpu.index ? t.accent : t.textTertiary,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    gpu.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: options.gpuId == gpu.index ? t.textPrimary : t.textSecondary,
                      fontWeight: options.gpuId == gpu.index ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  '#${gpu.index}',
                  style: text.labelSmall?.copyWith(color: t.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),
        ],
      ],
    );
  }
}

class _TileSelector extends StatelessWidget {
  const _TileSelector({required this.options, required this.onChanged});

  final UpscaleOptions options;
  final ValueChanged<UpscaleOptions> onChanged;

  // ncnn 要求分块不小于 32；256 以上对多数显卡已经能覆盖常见照片。
  static const List<({int value, String label})> _choices = [
    (value: 0, label: '自动'),
    (value: 64, label: '64'),
    (value: 128, label: '128'),
    (value: 256, label: '256'),
    (value: 512, label: '512'),
  ];

  @override
  Widget build(BuildContext context) {
    return SegmentedControl<int>(
      value: options.tileSize,
      onChanged: (v) => onChanged(options.copyWith(tileSize: v)),
      segments: [
        for (final c in _choices) Segment(c.value, c.label),
      ],
    );
  }
}

/// 运行时信息与维护操作。
class _RuntimeSection extends StatelessWidget {
  const _RuntimeSection();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final scope = AppScope.of(context);
    final runtime = scope.runtime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('运行环境'),
        Panel(
          padding: const EdgeInsets.all(Gap.md),
          color: t.surfaceSunken,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(
                label: '推理引擎',
                value: runtime.isReady ? '已就绪' : '未安装',
                icon: Symbols.terminal,
                valueColor: runtime.isReady ? t.success : t.danger,
              ),
              InfoRow(
                label: '模型数量',
                value: '${runtime.models.value.length}',
                icon: Symbols.layers,
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),

        const SectionLabel('并行任务数'),
        SegmentedControl<int>(
          value: scope.settings.concurrency,
          onChanged: (v) => scope.settings.concurrency = v,
          segments: const [
            Segment(1, '1 个', caption: '推荐'),
            Segment(2, '2 个', caption: '显存充足'),
            Segment(3, '3 个', caption: '高速卡'),
          ],
        ),
        const SizedBox(height: Gap.sm),
        Text(
          '同一块显卡上并行跑多个推理进程收益有限——算力本来就是瓶颈——'
          '但显存占用会成倍增加。只有当队列里参数不同的任务很多时才值得调高。',
          style: text.labelSmall?.copyWith(color: t.textTertiary, height: 1.4),
        ),
        const SizedBox(height: Gap.xl),

        SwitchRow(
          label: '处理时阻止休眠',
          detail: '避免长时间批处理被系统睡眠打断',
          value: scope.settings.preventSleep,
          onChanged: (v) => scope.settings.preventSleep = v,
        ),
        SwitchRow(
          label: '完成后提示音',
          detail: '有文件成功处理完毕时提醒',
          value: scope.settings.playSoundWhenDone,
          onChanged: (v) => scope.settings.playSoundWhenDone = v,
        ),
        SwitchRow(
          label: '完成后打开输出目录',
          detail: '自动在资源管理器中定位结果',
          value: scope.settings.revealWhenDone,
          onChanged: (v) => scope.settings.revealWhenDone = v,
        ),
      ],
    );
  }
}
