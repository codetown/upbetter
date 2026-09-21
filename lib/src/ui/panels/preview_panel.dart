import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/models.dart';
import '../../core/util/format.dart';
import '../theme/tokens.dart';
import '../util/system.dart';
import '../widgets/primitives.dart';
import 'compare_canvas.dart';
import 'queue_panel.dart';
import 'settings_panel.dart';
import 'status_bar.dart';
import '../shell/title_bar.dart';

/// 中间的预览面板：工具栏 + 对比画布。
class PreviewPanel extends StatefulWidget {
  const PreviewPanel({super.key, required this.selected});

  final ValueNotifier<UpscaleJob?> selected;

  @override
  State<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  final GlobalKey<CompareCanvasState> _canvasKey =
      GlobalKey<CompareCanvasState>();

  ViewMode _mode = ViewMode.split;

  /// 按住空格时临时切到原图，松开恢复——这是修图工具里最顺手的对比手势。
  ViewMode? _modeBeforePeek;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);

    return ValueListenableBuilder<UpscaleJob?>(
      valueListenable: widget.selected,
      builder: (context, job, _) {
        if (job == null) {
          return Container(
            color: t.canvas,
            child: const EmptyState(
              icon: Symbols.photo_size_select_large,
              title: '选择一张图片开始',
              message: '从左侧队列中点击任意文件即可在此预览。\n放大完成后，这里会自动切换为前后对比视图。',
            ),
          );
        }

        return Container(
          color: t.canvas,
          child: Stack(
            children: [
              Positioned.fill(
                child: _CanvasHost(
                  job: job,
                  mode: _effectiveMode(job),
                  canvasKey: _canvasKey,
                  onJobSized: _scheduleFit,
                  viewportInsets: const EdgeInsets.fromLTRB(
                    QueuePanel.width + 1,
                    TitleBar.defaultHeight,
                    SettingsPanel.width + 1,
                    StatusBar.height,
                  ),
                ),
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(height: 42),
              ),
              Positioned(
                top: 42,
                left: 0,
                right: 0,
                child: _Toolbar(
                  job: job,
                  mode: _mode,
                  onModeChanged: _setMode,
                  onFit: _fit,
                  onActualSize: _actualSize,
                  onZoomIn: () => _zoom(1.25),
                  onZoomOut: () => _zoom(0.8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // 用全局键盘钩子而不是 Focus：预览区未必持有焦点，
    // 但「按住空格看原图」应当在任何时候都可用。
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  ViewMode _effectiveMode(UpscaleJob job) {
    final hasResult = _hasResult(job);
    if (!hasResult) return ViewMode.original;
    if (_mode == ViewMode.result && !hasResult) return ViewMode.original;
    return _mode;
  }

  static bool _hasResult(UpscaleJob job) {
    final path = job.outputPath.value;
    return job.status.value == JobStatus.done &&
        path != null &&
        File(path).existsSync();
  }

  void _setMode(ViewMode mode) {
    setState(() => _mode = mode);
    _scheduleFit();
  }

  bool _onKey(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space) return false;
    // 正在输入框里打字时不要抢走空格。
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.widget is EditableText ||
        focus?.context?.widget is TextField) {
      return false;
    }
    if (event is KeyDownEvent) {
      if (_modeBeforePeek == null) {
        _modeBeforePeek = _mode;
        setState(() => _mode = ViewMode.original);
      }
    } else if (event is KeyUpEvent && _modeBeforePeek != null) {
      setState(() => _mode = _modeBeforePeek!);
      _modeBeforePeek = null;
    }
    return true;
  }

  void _scheduleFit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _canvasKey.currentState;
      final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
      if (state == null || box == null) return;
      state.fitToViewport(box.size);
    });
  }

  void _fit() => _scheduleFit();

  void _actualSize() {
    final state = _canvasKey.currentState;
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (state == null || box == null) return;
    state.zoomToActualSize(box.size);
  }

  void _zoom(double factor) {
    final state = _canvasKey.currentState;
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (state == null || box == null) return;
    state.zoomBy(factor, box.size);
  }
}

class _CanvasHost extends StatefulWidget {
  const _CanvasHost({
    required this.job,
    required this.mode,
    required this.canvasKey,
    required this.onJobSized,
    required this.viewportInsets,
  });

  final UpscaleJob job;
  final ViewMode mode;
  final GlobalKey<CompareCanvasState> canvasKey;
  final VoidCallback onJobSized;
  final EdgeInsets viewportInsets;

  @override
  State<_CanvasHost> createState() => _CanvasHostState();
}

class _CanvasHostState extends State<_CanvasHost> {
  @override
  void initState() {
    super.initState();
    widget.onJobSized();
  }

  @override
  void didUpdateWidget(_CanvasHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换到另一个文件、或结果刚刚生成时，视图需要重新适配。
    if (oldWidget.job.id != widget.job.id ||
        oldWidget.mode != widget.mode ||
        oldWidget.job.outputWidth != widget.job.outputWidth ||
        oldWidget.job.outputHeight != widget.job.outputHeight) {
      widget.onJobSized();
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    // 任务完成的那一刻，预览需要立刻从「原图」切换到「对比」。
    return ValueListenableBuilder<JobStatus>(
      valueListenable: job.status,
      builder: (context, _, _) => ValueListenableBuilder<String?>(
        valueListenable: job.outputPath,
        builder: (context, outputPath, _) {
          final hasResult =
              job.status.value == JobStatus.done &&
              outputPath != null &&
              File(outputPath).existsSync();

          final source = Size(
            job.sourceInfo.width.toDouble(),
            job.sourceInfo.height.toDouble(),
          );
          final result = Size(
            job.outputWidth.toDouble(),
            job.outputHeight.toDouble(),
          );

          // 对比模式下两层必须使用同一套坐标：以结果图的尺寸为基准，
          // 原图会被拉伸到同样的尺寸，这样看到的才是
          // 「AI 放大」与「直接插值放大」之间的真实差异。
          final logical = hasResult ? result : source;

          return CompareCanvas(
            key: widget.canvasKey,
            beforePath: job.inputPath,
            afterPath: hasResult ? outputPath : null,
            logicalSize: logical,
            mode: hasResult ? widget.mode : ViewMode.original,
            viewportInsets: widget.viewportInsets,
          );
        },
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.job,
    required this.mode,
    required this.onModeChanged,
    required this.onFit,
    required this.onActualSize,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final UpscaleJob job;
  final ViewMode mode;
  final ValueChanged<ViewMode> onModeChanged;
  final VoidCallback onFit;
  final VoidCallback onActualSize;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final hasResult = _PreviewPanelState._hasResult(job);

    final sourceSize = Size(
      job.sourceInfo.width.toDouble(),
      job.sourceInfo.height.toDouble(),
    );
    final resultSize = Size(
      job.outputWidth.toDouble(),
      job.outputHeight.toDouble(),
    );
    final shownSize = mode == ViewMode.original && !hasResult
        ? sourceSize
        : resultSize;

    return GlassSurface(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      border: Border(bottom: BorderSide(color: t.border)),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    job.inputName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Text(
                  Fmt.dimensions(
                    shownSize.width.toInt(),
                    shownSize.height.toInt(),
                  ),
                  style: text.labelSmall?.copyWith(
                    color: t.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (hasResult) ...[
                  const SizedBox(width: Gap.sm),
                  StatusBadge(
                    label: Fmt.scale(job.options.scale.toDouble()),
                    color: t.accent,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
          if (hasResult)
            SegmentedControl<ViewMode>(
              expand: false,
              value: mode,
              onChanged: onModeChanged,
              segments: const [
                Segment(ViewMode.split, '对比'),
                Segment(ViewMode.original, '原图'),
                Segment(ViewMode.result, '结果'),
              ],
            )
          else
            StatusBadge(
              label: job.status.value == JobStatus.running ? '处理中' : '尚未放大',
              color: job.status.value == JobStatus.running
                  ? t.accent
                  : t.textTertiary,
            ),
          const SizedBox(width: Gap.md),
          IconBtn(icon: Symbols.zoom_out, tooltip: '缩小', onPressed: onZoomOut),
          IconBtn(icon: Symbols.zoom_in, tooltip: '放大', onPressed: onZoomIn),
          IconBtn(
            icon: Symbols.fit_screen,
            tooltip: '适应窗口  (双击画布)',
            onPressed: onFit,
          ),
          IconBtn(
            icon: Symbols.crop_free,
            tooltip: '实际像素 1:1',
            onPressed: onActualSize,
          ),
          if (hasResult) ...[
            const SizedBox(width: Gap.xs),
            IconBtn(
              icon: Symbols.folder_open,
              tooltip: '在资源管理器中显示结果',
              onPressed: () => SystemShell.revealFile(job.outputPath.value!),
            ),
          ],
        ],
      ),
    );
  }
}
