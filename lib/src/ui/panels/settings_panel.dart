import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/engine/upscale_engine.dart';
import '../../core/models.dart';
import '../../core/util/format.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../widgets/primitives.dart';
import 'advanced_settings.dart';
import 'output_settings.dart';

/// 右侧参数面板：模型、倍率、输出、高级选项，以及底部的主操作按钮。
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, required this.selected});

  final ValueNotifier<UpscaleJob?> selected;

  static const double width = 348;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  bool _advancedOpen = false;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final scope = AppScope.of(context);

    return Container(
      width: SettingsPanel.width,
      color: t.surface,
      child: ListenableBuilder(
        listenable: Listenable.merge([scope.settings, scope.runtime]),
        builder: (context, _) {
          final options = scope.settings.options;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.md),
                  children: [
                    ModelSection(
                      options: options,
                      models: scope.runtime.models.value,
                      onChanged: _update,
                    ),
                    const SizedBox(height: Gap.xl),
                    ScaleSection(
                      options: options,
                      selected: widget.selected,
                      onChanged: _update,
                    ),
                    const SizedBox(height: Gap.xl),
                    OutputSettingsSection(options: options, onChanged: _update),
                    const SizedBox(height: Gap.xl),
                    _AdvancedToggle(
                      open: _advancedOpen,
                      onTap: () => setState(() => _advancedOpen = !_advancedOpen),
                    ),
                    AnimatedSize(
                      duration: Motion.normal,
                      curve: Motion.emphasized,
                      alignment: Alignment.topCenter,
                      child: _advancedOpen
                          ? Padding(
                              padding: const EdgeInsets.only(top: Gap.lg),
                              child: AdvancedSettingsSection(
                                options: options,
                                gpus: scope.runtime.gpus.value,
                                onChanged: _update,
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
              _PanelFooter(selected: widget.selected),
            ],
          );
        },
      ),
    );
  }

  void _update(UpscaleOptions options) {
    final scope = AppScope.of(context);
    scope.settings.options = options;
    // 参数是全局的：改完之后待处理队列应当立刻跟上，
    // 否则用户会以为自己的修改没有生效。
    scope.engine.applyOptionsToPending(options);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 模型
// ─────────────────────────────────────────────────────────────────────────────

class ModelSection extends StatelessWidget {
  const ModelSection({
    super.key,
    required this.options,
    required this.models,
    required this.onChanged,
  });

  final UpscaleOptions options;
  final List<ModelSpec> models;
  final ValueChanged<UpscaleOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    if (models.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('放大模型'),
          Panel(
            padding: const EdgeInsets.all(Gap.md),
            color: t.surfaceSunken,
            child: Row(
              children: [
                Icon(Symbols.warning, size: 16, color: t.warning),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text('未找到任何模型权重文件', style: text.bodySmall),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 设置里记录的模型可能已被删除，回退到第一个可用项。
    final activeId =
        models.any((m) => m.id == options.modelId) ? options.modelId : models.first.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          '放大模型',
          trailing: Text(
            '${models.length} 个可用',
            style: text.labelSmall?.copyWith(color: t.textTertiary),
          ),
        ),
        for (final model in models) ...[
          SelectableCard(
            selected: model.id == activeId,
            onTap: () => onChanged(options.copyWith(modelId: model.id)),
            child: _ModelCardBody(model: model, selected: model.id == activeId),
          ),
          const SizedBox(height: Gap.sm),
        ],
      ],
    );
  }
}

class _ModelCardBody extends StatelessWidget {
  const _ModelCardBody({required this.model, required this.selected});

  final ModelSpec model;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: Motion.fast,
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? t.accent : Colors.transparent,
            border: Border.all(
              color: selected ? t.accent : t.borderStrong,
              width: 1.5,
            ),
          ),
          child: selected ? const Icon(Symbols.check, size: 12, color: Colors.white) : null,
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      model.displayName,
                      style: text.titleSmall?.copyWith(
                        color: selected ? t.textPrimary : t.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    Fmt.bytes(model.sizeBytes),
                    style: text.labelSmall?.copyWith(color: t.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                model.category.description,
                style: text.labelSmall?.copyWith(color: t.textTertiary, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 倍率
// ─────────────────────────────────────────────────────────────────────────────

class ScaleSection extends StatelessWidget {
  const ScaleSection({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final UpscaleOptions options;
  final ValueNotifier<UpscaleJob?> selected;
  final ValueChanged<UpscaleOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('放大倍率'),
        SegmentedControl<int>(
          value: options.scale,
          onChanged: (value) => onChanged(options.copyWith(scale: value)),
          segments: const [
            Segment(2, '2×', caption: '快速'),
            Segment(3, '3×', caption: '均衡'),
            Segment(4, '4×', caption: '最大'),
          ],
        ),
        const SizedBox(height: Gap.sm),
        ValueListenableBuilder<UpscaleJob?>(
          valueListenable: selected,
          builder: (context, job, _) {
            if (job == null) return const SizedBox.shrink();
            final outW = job.sourceInfo.width * options.scale;
            final outH = job.sourceInfo.height * options.scale;
            return InfoRow(
              label: '输出尺寸',
              value: Fmt.dimensions(outW, outH),
              icon: Symbols.aspect_ratio,
            );
          },
        ),
        ValueListenableBuilder<UpscaleJob?>(
          valueListenable: selected,
          builder: (context, job, _) {
            final modelId = options.modelId;
            final model = findModel(modelId);
            final native = model?.nativeScale ?? options.scale;
            if (options.scale == native) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: Text(
                '该模型的原生倍率是 $native×，选择 ${options.scale}× 会先按 $native× 推理再降采样，'
                '画质仍然明显优于直接插值。',
                style: text.labelSmall?.copyWith(color: t.textTertiary, height: 1.4),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 高级选项折叠开关
// ─────────────────────────────────────────────────────────────────────────────

class _AdvancedToggle extends StatefulWidget {
  const _AdvancedToggle({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  State<_AdvancedToggle> createState() => _AdvancedToggleState();
}

class _AdvancedToggleState extends State<_AdvancedToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Gap.sm, horizontal: Gap.md),
          decoration: BoxDecoration(
            color: _hovered ? t.surfaceElevated : Colors.transparent,
            borderRadius: Radii.allSm,
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Icon(Symbols.tune, size: 15, color: t.textSecondary),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text('高级选项', style: Theme.of(context).textTheme.titleSmall),
              ),
              AnimatedRotation(
                turns: widget.open ? 0.5 : 0,
                duration: Motion.fast,
                curve: Motion.standard,
                child: Icon(Symbols.expand_more, size: 18, color: t.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 底部主操作区
// ─────────────────────────────────────────────────────────────────────────────

class _PanelFooter extends StatelessWidget {
  const _PanelFooter({required this.selected});

  final ValueNotifier<UpscaleJob?> selected;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final engine = AppScope.of(context).engine;

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: ListenableBuilder(
        listenable: engine,
        builder: (context, _) {
          final running = engine.isRunning;
          final stopping = engine.state.value == QueueState.stopping;
          final pending = engine.pendingCount;
          final done = engine.completedCount;
          final failed = engine.failedCount;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (running) ...[
                _ProgressSummary(engine: engine, selected: selected),
                const SizedBox(height: Gap.md),
              ] else if (pending > 0) ...[
                _EstimateRow(engine: engine),
                const SizedBox(height: Gap.md),
              ],
              GradientButton(
                label: _buttonLabel(running, stopping, pending, engine.jobs.isEmpty),
                icon: running ? Symbols.stop : Symbols.rocket_launch,
                busy: stopping,
                onPressed: running
                    ? engine.stop
                    : (pending > 0 ? engine.start : null),
              ),
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _hintLabel(running, engine.jobs.isEmpty, failed),
                      style: text.labelSmall?.copyWith(color: t.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (done > 0 || failed > 0)
                    Text(
                      '$done 成功${failed > 0 ? ' · $failed 失败' : ''}',
                      style: text.labelSmall?.copyWith(
                        color: failed > 0 ? t.danger : t.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 开始之前的耗时预估。
///
/// 依据是同机型同参数的历史实测吞吐量，因此第一次使用某个组合时无从估计——
/// 这时诚实地说明「还没有数据」，比给一个可能差十倍的数字要好。
class _EstimateRow extends StatelessWidget {
  const _EstimateRow({required this.engine});

  final UpscaleEngine engine;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final settings = AppScope.of(context).settings;

    final pendingJobs = engine.jobs
        .where((j) => j.status.value == JobStatus.queued)
        .toList();
    if (pendingJobs.isEmpty) return const SizedBox.shrink();

    final options = settings.options;
    // 只统计与当前参数一致的任务——改了倍率之后，旧任务的像素量不能直接相加。
    final matching = pendingJobs
        .where((j) => j.options.executionKey == options.executionKey)
        .toList();
    final pixels = matching.fold<int>(0, (sum, j) => sum + j.outputPixels);
    final estimate = engine.estimateDuration(options, pixels);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: Radii.allSm,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(Symbols.schedule, size: 14, color: t.textTertiary),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              estimate == null ? '耗时预估' : '预计耗时',
              style: text.labelMedium?.copyWith(color: t.textSecondary),
            ),
          ),
          Text(
            estimate == null ? '首次运行后可知' : Fmt.compactDuration(estimate),
            style: text.labelMedium?.copyWith(
              color: estimate == null ? t.textTertiary : t.textPrimary,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 主按钮的文案。空队列和处理完是两种不同状态，不该用同一句话打发用户。
String _buttonLabel(bool running, bool stopping, int pending, bool empty) {
  if (running) return stopping ? '正在停止…' : '停止';
  if (pending > 0) return '开始放大  ·  $pending 个文件';
  if (empty) return '先添加图片';
  return '队列已处理完';
}

String _hintLabel(bool running, bool empty, int failed) {
  if (running) return '未处理的任务会在停止后保留在队列中';
  if (empty) return '拖入图片或文件夹即可开始';
  if (failed > 0) return '有 $failed 个文件失败，可在队列右上角重试';
  return '按 Ctrl+Enter 快速开始';
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({required this.engine, required this.selected});

  final UpscaleEngine engine;
  final ValueNotifier<UpscaleJob?> selected;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    return ValueListenableBuilder<double>(
      valueListenable: engine.overallProgress,
      builder: (context, progress, _) => ValueListenableBuilder<Duration>(
        valueListenable: engine.eta,
        builder: (context, eta, _) => ValueListenableBuilder<double>(
          valueListenable: engine.throughput,
          builder: (context, throughput, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '总体进度',
                        style: text.labelMedium?.copyWith(color: t.textSecondary),
                      ),
                    ),
                    Text(
                      Fmt.percent(progress, digits: 1),
                      style: text.labelMedium?.copyWith(
                        color: t.accent,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.linear,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      backgroundColor: t.surfaceSunken,
                    ),
                  ),
                ),
                if (eta.inSeconds > 0 || throughput > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (eta.inSeconds > 0)
                        Text(
                          Fmt.eta(eta),
                          style: text.labelSmall?.copyWith(color: t.textTertiary),
                        ),
                      const Spacer(),
                      if (throughput > 0)
                        Text(
                          '${(throughput / 1e6).toStringAsFixed(2)} MP/s',
                          style: text.labelSmall?.copyWith(
                            color: t.textTertiary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
