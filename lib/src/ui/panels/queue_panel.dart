import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/engine/upscale_engine.dart';
import '../../core/models.dart';
import '../../core/util/format.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../util/system.dart';
import '../widgets/primitives.dart';

/// 左侧队列面板。
///
/// 每一行只订阅自己那个任务的 [ValueNotifier]，因此在处理上百个文件时，
/// 一个任务的进度跳动只会重建那一行，不会引起整个列表重排。
class QueuePanel extends StatelessWidget {
  const QueuePanel({
    super.key,
    required this.selected,
    required this.onPickFiles,
    required this.onPickFolder,
  });

  final ValueNotifier<UpscaleJob?> selected;
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;

  static const double width = 306;
  static const double _rowHeight = 62;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final engine = AppScope.of(context).engine;

    return Container(
      width: width,
      color: t.surface,
      child: Column(
        children: [
          _Header(engine: engine, onPickFiles: onPickFiles, onPickFolder: onPickFolder),
          Divider(color: t.border, height: 1),
          Expanded(
            child: ListenableBuilder(
              listenable: engine,
              builder: (context, _) {
                final jobs = engine.jobs;
                if (jobs.isEmpty) {
                  return _EmptyQueue(onPickFiles: onPickFiles, onPickFolder: onPickFolder);
                }
                return ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: Gap.sm, horizontal: Gap.sm),
                  itemCount: jobs.length,
                  itemExtent: _rowHeight,
                  // 关掉默认手柄：桌面端它会接管整个条目的拖拽，
                  // 跟我们需要的「点击选中、拖手柄才排序」冲突。
                  buildDefaultDragHandles: false,
                  onReorderItem: engine.reorderJob,
                  proxyDecorator: (child, index, animation) => _DragProxy(
                    animation: animation,
                    tokens: t,
                    child: child,
                  ),
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return _JobRow(
                      key: ValueKey(job.id),
                      index: index,
                      job: job,
                      selected: selected,
                      onCancel: () {
                        if (selected.value == job) selected.value = null;
                        engine.cancelJob(job);
                      },
                      onRemove: () {
                        if (selected.value == job) selected.value = null;
                        engine.removeJob(job);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 拖拽中的条目：抬起来并加一点阴影，让「正在移动」这件事有实感。
class _DragProxy extends StatelessWidget {
  const _DragProxy({
    required this.child,
    required this.animation,
    required this.tokens,
  });

  final Widget child;
  final Animation<double> animation;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t0 = Curves.easeOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.015 * t0,
          child: Material(
            color: Colors.transparent,
            elevation: 8 * t0,
            shadowColor: Colors.black.withValues(alpha: 0.5),
            borderRadius: Radii.allMd,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.surfaceElevated,
                borderRadius: Radii.allMd,
                border: Border.all(color: t.accent.withValues(alpha: 0.5)),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.engine,
    required this.onPickFiles,
    required this.onPickFolder,
  });

  final UpscaleEngine engine;
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.sm, Gap.sm),
      child: Column(
        children: [
          Row(
            children: [
              Text('队列', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: Gap.sm),
              ListenableBuilder(
                listenable: engine,
                builder: (context, _) {
                  final total = engine.jobs.length;
                  if (total == 0) return const SizedBox.shrink();
                  return StatusBadge(
                    label: '$total',
                    color: t.textTertiary,
                    dense: true,
                  );
                },
              ),
              const Spacer(),
              IconBtn(
                icon: Symbols.note_add,
                tooltip: '添加文件  (Ctrl+O)',
                onPressed: onPickFiles,
              ),
              IconBtn(
                icon: Symbols.folder_open,
                tooltip: '添加文件夹  (Ctrl+Shift+O)',
                onPressed: onPickFolder,
              ),
              _MoreMenu(engine: engine),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.engine});

  final UpscaleEngine engine;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final hasFinished = engine.jobs.any((j) => j.status.value.isTerminal);
        final hasFailed = engine.jobs.any((j) {
          final s = j.status.value;
          return s == JobStatus.failed || s == JobStatus.canceled;
        });
        if (!hasFinished && engine.jobs.isEmpty) {
          return const SizedBox(width: 4);
        }

        return PopupMenuButton<String>(
          tooltip: '更多',
          icon: Icon(Symbols.more_vert, size: 18, color: t.textSecondary),
          splashRadius: 16,
          onSelected: (value) {
            switch (value) {
              case 'retry':
                engine.retryFailed();
              case 'clear':
                engine.clearFinished();
              case 'clear_all':
                engine.clearAll();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'retry',
              enabled: hasFailed,
              child: const _MenuRow(icon: Symbols.restart_alt, label: '重试失败项'),
            ),
            PopupMenuItem(
              value: 'clear',
              enabled: hasFinished,
              child: const _MenuRow(icon: Symbols.delete_sweep, label: '清除已完成'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'clear_all',
              child: _MenuRow(icon: Symbols.delete, label: '清空队列', danger: true),
            ),
          ],
        );
      },
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.danger = false});

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final color = danger ? t.danger : t.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: Gap.md),
        Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
      ],
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.onPickFiles, required this.onPickFolder});

  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.photo_library, size: 34, color: t.textTertiary),
            const SizedBox(height: Gap.md),
            Text(
              '队列是空的',
              style: text.titleSmall?.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              '把图片或文件夹拖到窗口任意位置',
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Gap.lg),
            OutlinedButton.icon(
              onPressed: onPickFiles,
              icon: const Icon(Symbols.add, size: 16),
              label: const Text('选择图片'),
            ),
            const SizedBox(height: Gap.sm),
            TextButton(
              onPressed: onPickFolder,
              child: const Text('或选择文件夹'),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobRow extends StatefulWidget {
  const _JobRow({
    super.key,
    required this.index,
    required this.job,
    required this.selected,
    required this.onCancel,
    required this.onRemove,
  });

  final int index;
  final UpscaleJob job;
  final ValueNotifier<UpscaleJob?> selected;
  final VoidCallback onCancel;
  final VoidCallback onRemove;

  @override
  State<_JobRow> createState() => _JobRowState();
}

class _JobRowState extends State<_JobRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);

    return ValueListenableBuilder<UpscaleJob?>(
      valueListenable: widget.selected,
      builder: (context, current, _) {
        final isSelected = identical(current, widget.job);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () => widget.selected.value = widget.job,
            onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.standard,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? t.accentSoft
                    : _hovered
                        ? t.surfaceElevated
                        : Colors.transparent,
                borderRadius: Radii.allMd,
                border: Border.all(
                  color: isSelected ? t.accent.withValues(alpha: 0.45) : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  _DragHandle(index: widget.index, visible: _hovered, tokens: t),
                  _Thumbnail(job: widget.job),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: _Details(
                      job: widget.job,
                      onCancel: widget.onCancel,
                      onRemove: widget.onRemove,
                      hovered: _hovered,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final job = widget.job;
    final output = job.outputPath.value;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'reveal', child: _MenuRow(icon: Symbols.folder_open, label: '打开所在文件夹')),
        if (output != null)
          const PopupMenuItem(value: 'reveal_out', child: _MenuRow(icon: Symbols.image, label: '定位输出文件')),
        const PopupMenuDivider(),
        if (!job.status.value.isTerminal)
          const PopupMenuItem(value: 'cancel', child: _MenuRow(icon: Symbols.cancel, label: '取消此任务')),
        if (job.status.value != JobStatus.queued)
          const PopupMenuItem(value: 'retry', child: _MenuRow(icon: Symbols.restart_alt, label: '重新排队')),
        const PopupMenuItem(value: 'remove', child: _MenuRow(icon: Symbols.close, label: '从队列移除', danger: true)),
      ],
    );

    switch (result) {
      case 'reveal':
        await SystemShell.revealFile(job.inputPath);
      case 'reveal_out':
        if (output != null && File(output).existsSync()) {
          await SystemShell.revealFile(output);
        }
      case 'cancel':
        widget.onCancel();
      case 'retry':
        job.status.value = JobStatus.queued;
        job.progress.value = 0;
        job.errorMessage.value = null;
      case 'remove':
        widget.onRemove();
    }
  }
}

/// 拖拽手柄。只在悬停时出现，避免静止状态下干扰视觉。
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.index, required this.visible, required this.tokens});

  final int index;
  final bool visible;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    // 用 ReorderableDragStartListener 而不是 Delayed：桌面端用户期望
    // 按住手柄立即开始拖动，而不是像移动端那样先长按。
    return ReorderableDragStartListener(
      index: index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: Motion.instant,
          child: SizedBox(
            width: 22,
            height: 46,
            child: Icon(
              Symbols.drag_indicator,
              size: 15,
              color: tokens.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 缩略图。
///
/// 关键性能点：通过 `cacheWidth` 让原生解码器**在解码阶段**就把图像缩到目标尺寸，
/// 而不是先解出全尺寸位图再缩放。对一张 8000×6000 的照片，前者只需几毫秒，
/// 后者要分配近 200 MB 内存。
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.job});

  final UpscaleJob job;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);

    return ValueListenableBuilder<String?>(
      valueListenable: job.outputPath,
      builder: (context, outputPath, _) {
        final hasResult = job.status.value == JobStatus.done &&
            outputPath != null &&
            File(outputPath).existsSync();
        final path = hasResult ? outputPath : job.inputPath;

        return Padding(
          padding: const EdgeInsets.only(left: Gap.sm),
          child: ClipRRect(
            borderRadius: Radii.allSm,
            child: Container(
              width: 46,
              height: 46,
              color: t.surfaceSunken,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: CheckerboardPainter(light: t.checkerLight, dark: t.checkerDark, cellSize: 6)),
                  Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    cacheWidth: 92,
                    cacheHeight: 92,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (context, _, _) => Icon(
                      Symbols.broken_image,
                      size: 18,
                      color: t.textTertiary,
                    ),
                  ),
                  if (hasResult)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          color: t.success,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Symbols.check, size: 9, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.job,
    required this.onCancel,
    required this.onRemove,
    required this.hovered,
  });

  final UpscaleJob job;
  final VoidCallback onCancel;
  final VoidCallback onRemove;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(right: Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.inputName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              // 一个按钮承担两种语义：还没做完的是「取消」，
              // 已经有结果的是「移除」。这样鼠标不用在多个按钮之间找。
              ValueListenableBuilder<JobStatus>(
                valueListenable: job.status,
                builder: (context, status, _) {
                  final cancellable = !status.isTerminal;
                  return SizedBox(
                    width: 20,
                    height: 20,
                    child: AnimatedOpacity(
                      opacity: hovered ? 1 : 0,
                      duration: Motion.instant,
                      child: IconBtn(
                        icon: cancellable ? Symbols.cancel : Symbols.close,
                        tooltip: cancellable ? '取消此任务' : '从队列移除',
                        size: 20,
                        iconSize: 13,
                        onPressed: hovered ? (cancellable ? onCancel : onRemove) : null,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 3),
          ValueListenableBuilder<JobStatus>(
            valueListenable: job.status,
            builder: (context, status, _) {
              return ValueListenableBuilder<double>(
                valueListenable: job.progress,
                builder: (context, progress, _) {
                  return _StatusLine(job: job, status: status, progress: progress, tokens: t);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.job,
    required this.status,
    required this.progress,
    required this.tokens,
  });

  final UpscaleJob job;
  final JobStatus status;
  final double progress;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final text = Theme.of(context).textTheme;

    if (status == JobStatus.running) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 140),
              curve: Curves.linear,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 3,
                backgroundColor: t.surfaceSunken,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${Fmt.percent(progress)} · ${Fmt.dimensions(job.outputWidth, job.outputHeight)}',
            style: text.labelSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      );
    }

    if (status == JobStatus.failed) {
      return Row(
        children: [
          Icon(Symbols.error, size: 11, color: t.danger),
          const SizedBox(width: 4),
          Expanded(
            child: ValueListenableBuilder<String?>(
              valueListenable: job.errorMessage,
              builder: (context, message, _) => Text(
                message ?? '处理失败',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(color: t.danger),
              ),
            ),
          ),
        ],
      );
    }

    // 完成后顺带把实测耗时显示出来，用户才知道这张图到底花了多久。
    final elapsedSuffix = status == JobStatus.done
        ? ' · ${Fmt.compactDuration(job.elapsed.value)}'
        : '';

    final (label, color) = switch (status) {
      JobStatus.done => (
          '完成 · ${Fmt.dimensions(job.outputWidth, job.outputHeight)}$elapsedSuffix',
          t.success,
        ),
      JobStatus.canceled => ('已取消', t.textTertiary),
      JobStatus.queued => (
          '${Fmt.dimensions(job.sourceInfo.width, job.sourceInfo.height)} · 排队中',
          t.textTertiary,
        ),
      _ => ('', t.textTertiary),
    };

    return Row(
      children: [
        if (status == JobStatus.done) ...[
          Icon(Symbols.check_circle, size: 11, color: t.success),
          const SizedBox(width: 4),
        ] else if (status == JobStatus.canceled) ...[
          Icon(Symbols.cancel, size: 11, color: t.textTertiary),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
