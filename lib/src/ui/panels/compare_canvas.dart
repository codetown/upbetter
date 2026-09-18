import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/primitives.dart';

enum ViewMode {
  split('对比'),
  original('原图'),
  result('结果');

  const ViewMode(this.label);

  final String label;
}

/// 高性能图像对比画布。
///
/// 三处关键设计：
/// 1. **分级解码**：先解码一张长边 2048 的预览图保证秒开，当用户放大到接近
///    1:1 时再后台解码高分辨率版本并平滑替换。这既避免了打开 8000×6000 照片时
///    的长时间等待，也绕开了超大纹理超过 GPU 上限的问题。
/// 2. **手动变换**：不依赖 `InteractiveViewer`，自己维护缩放/平移矩阵。
///    这样缩放可以精确锚定在鼠标指针上，并且平移缩放不触发布局，只走合成。
/// 3. **双图层裁剪**：对比分割线固定在屏幕空间，两张图共享同一个变换矩阵，
///    拖动分割线时看到的是同一位置的内容，符合「放大镜」式的直觉。
class CompareCanvas extends StatefulWidget {
  const CompareCanvas({
    super.key,
    required this.beforePath,
    required this.afterPath,
    required this.logicalSize,
    required this.mode,
  });

  final String? beforePath;
  final String? afterPath;

  /// 图像的逻辑尺寸（原始像素）。布局始终按它计算，
  /// 这样从低清预览切换到高清时不会发生跳变。
  final Size logicalSize;

  final ViewMode mode;

  @override
  State<CompareCanvas> createState() => CompareCanvasState();
}

class CompareCanvasState extends State<CompareCanvas> {
  final TransformationController _controller = TransformationController();

  double _split = 0.5;
  bool _draggingSplit = false;
  bool _panning = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 适配窗口：让整张图完整可见并居中。
  /// 构造「先缩放、再平移」的变换矩阵。
  ///
  /// 画布的变换始终是纯缩放 + 纯平移（没有旋转/斜切），
  /// 因此用一个二维参数化就能完整表达，也让边界约束变得简单可靠。
  static Matrix4 _compose(double dx, double dy, double scale) => Matrix4.identity()
    ..translateByDouble(dx, dy, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);

  void fitToViewport(Size viewport) {
    if (viewport.isEmpty || widget.logicalSize.isEmpty) return;
    // 上限锁死在 1:1：这个工具的核心用途是判断放大质量，
    // 把小图拉伸到填满窗口会让人看到插值出来的假细节。
    final scale = math.min(
      1.0,
      math.min(
        viewport.width / widget.logicalSize.width,
        viewport.height / widget.logicalSize.height,
      ),
    );
    _controller.value = _compose(
      (viewport.width - widget.logicalSize.width * scale) / 2,
      (viewport.height - widget.logicalSize.height * scale) / 2,
      scale,
    );
    setState(() {});
  }

  /// 1:1 显示，以窗口中心为锚点。
  void zoomToActualSize(Size viewport) {
    final current = _controller.value.getMaxScaleOnAxis();
    final target = 1.0;
    final factor = target / current;
    _zoomAround(viewport.center(Offset.zero), factor, viewport);
  }

  double get currentScale => _controller.value.getMaxScaleOnAxis();

  /// 以视口中心为锚点缩放。供工具栏的 +/− 按钮使用。
  void zoomBy(double factor, Size viewport) {
    _zoomAround(viewport.center(Offset.zero), factor, viewport);
  }

  void _zoomAround(Offset focal, double factor, Size viewport) {
    final matrix = _controller.value;
    final currentScale = matrix.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(0.02, 16.0);
    if (nextScale == currentScale) return;

    final applied = nextScale / currentScale;
    // 保持焦点下的图像坐标不动：offset' = focal - (focal - offset) * applied
    final next = _compose(
      focal.dx - (focal.dx - matrix.storage[12]) * applied,
      focal.dy - (focal.dy - matrix.storage[13]) * applied,
      nextScale,
    );

    _controller.value = _constrain(next, viewport, nextScale);
    setState(() {});
  }

  /// 限制平移范围，保证图像始终有可见部分，避免「划出去找不回来」。
  Matrix4 _constrain(Matrix4 matrix, Size viewport, double scale) {
    final contentWidth = widget.logicalSize.width * scale;
    final contentHeight = widget.logicalSize.height * scale;
    // 允许拖到只剩 15% 可见，既能自由查看边缘，又不至于丢失目标。
    final marginX = math.min(viewport.width * 0.85, contentWidth * 0.85);
    final marginY = math.min(viewport.height * 0.85, contentHeight * 0.85);

    var dx = matrix.storage[12];
    var dy = matrix.storage[13];

    dx = dx.clamp(-contentWidth + marginX, viewport.width - marginX);
    dy = dy.clamp(-contentHeight + marginY, viewport.height - marginY);

    if (dx == matrix.storage[12] && dy == matrix.storage[13]) return matrix;
    return _compose(dx, dy, scale);
  }

  void _onPointerSignal(PointerSignalEvent event, Size viewport) {
    if (event is! PointerScrollEvent) return;
    final factor = math.exp(-event.scrollDelta.dy / 320);
    _zoomAround(event.localPosition, factor, viewport);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        if (viewport.isEmpty) return const SizedBox.shrink();

        return Listener(
          onPointerSignal: (event) => _onPointerSignal(event, viewport),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTapDown: (details) {
              // 双击在「适配」与「1:1」之间切换，是最常用的两个视图。
              if (currentScale > 0.9 && currentScale < 1.1) {
                fitToViewport(viewport);
              } else {
                zoomToActualSize(viewport);
              }
            },
            onPanStart: (_) => setState(() => _panning = true),
            onPanEnd: (_) => setState(() => _panning = false),
            onPanUpdate: (details) {
              final matrix = _controller.value;
              final scale = matrix.getMaxScaleOnAxis();
              final next = _compose(
                matrix.storage[12] + details.delta.dx,
                matrix.storage[13] + details.delta.dy,
                scale,
              );
              _controller.value = _constrain(next, viewport, scale);
              setState(() {});
            },
            child: MouseRegion(
              cursor: _panning ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      painter: _ViewportBackground(tokens: t),
                      child: _buildLayers(viewport),
                    ),
                  ),
                  if (widget.mode == ViewMode.split && widget.afterPath != null)
                    _SplitHandle(
                      position: _split * viewport.width,
                      height: viewport.height,
                      tokens: t,
                      dragging: _draggingSplit,
                      onDragStart: () => setState(() => _draggingSplit = true),
                      onDragEnd: () => setState(() => _draggingSplit = false),
                      onDrag: (dx) => setState(() {
                        _split = (_split + dx / viewport.width).clamp(0.0, 1.0);
                      }),
                    ),
                  Positioned(
                    left: Gap.md,
                    bottom: Gap.md,
                    child: _ZoomReadout(scale: currentScale, tokens: t),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLayers(Size viewport) {
    final matrix = _controller.value;
    final logical = widget.logicalSize;
    final showSplit = widget.mode == ViewMode.split && widget.afterPath != null;

    Widget layer(String? path, {required bool isResult}) {
      if (path == null) return const SizedBox.shrink();
      return Positioned(
        left: 0,
        top: 0,
        width: logical.width,
        height: logical.height,
        child: Transform(
          transform: matrix,
          child: SizedBox(
            width: logical.width,
            height: logical.height,
            child: _ImageLayerView(
              key: ValueKey('$path|$isResult'),
              path: path,
              logicalSize: logical,
              // 结果图通常比原图大得多，允许更高的解码上限。
              maxDecodeEdge: isResult ? 8192 : 6144,
              viewportScale: currentScale,
            ),
          ),
        ),
      );
    }

    final before = layer(widget.beforePath, isResult: false);
    final after = layer(widget.afterPath, isResult: true);

    if (!showSplit) {
      return Stack(
        clipBehavior: Clip.none,
        children: [before, if (widget.mode == ViewMode.result) after],
      );
    }

    // 对比模式：结果图层被裁剪到分割线左侧，分割线随窗口宽度固定。
    return Stack(
      clipBehavior: Clip.none,
      children: [
        before,
        Positioned.fill(
          child: ClipRect(
            clipper: _LeftFractionClipper(_split),
            child: Stack(clipBehavior: Clip.none, children: [after]),
          ),
        ),
      ],
    );
  }
}

/// 在屏幕空间按比例裁剪左侧区域。
class _LeftFractionClipper extends CustomClipper<Rect> {
  const _LeftFractionClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftFractionClipper oldClipper) => oldClipper.fraction != fraction;
}

class _ViewportBackground extends CustomPainter {
  const _ViewportBackground({required this.tokens});

  final AppTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = tokens.surfaceSunken);
    final paint = Paint()..color = tokens.border.withValues(alpha: 0.35);
    const gap = 22.0;
    for (var x = 0.0; x < size.width; x += gap) {
      for (var y = 0.0; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 0.9, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ViewportBackground oldDelegate) => oldDelegate.tokens != tokens;
}

/// 单个图像图层：负责分级解码与绘制。
class _ImageLayerView extends StatefulWidget {
  const _ImageLayerView({
    super.key,
    required this.path,
    required this.logicalSize,
    required this.maxDecodeEdge,
    required this.viewportScale,
  });

  final String path;
  final Size logicalSize;
  final int maxDecodeEdge;
  final double viewportScale;

  @override
  State<_ImageLayerView> createState() => _ImageLayerViewState();
}

class _ImageLayerViewState extends State<_ImageLayerView> {
  ui.Image? _preview;
  ui.Image? _detail;
  bool _loadingDetail = false;
  Timer? _detailDebounce;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _loadPreview();
    _maybeLoadDetail();
  }

  @override
  void didUpdateWidget(_ImageLayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _disposeImages();
      _loadPreview();
    }
    _maybeLoadDetail();
  }

  @override
  void dispose() {
    _detailDebounce?.cancel();
    _disposeImages();
    super.dispose();
  }

  void _disposeImages() {
    _preview?.dispose();
    _preview = null;
    _detail?.dispose();
    _detail = null;
    _loadingDetail = false;
  }

  Future<void> _loadPreview() async {
    final token = ++_loadToken;
    final image = await decodeImageCapped(widget.path, 2048);
    if (!mounted || token != _loadToken) {
      image?.dispose();
      return;
    }
    setState(() => _preview = image);
  }

  /// 只在用户放大到能看出差异时才加载高分辨率版本——这是一次
  /// 几百毫秒的解码，不应该在打开文件时就付出这个代价。
  void _maybeLoadDetail() {
    if (_detail != null || _loadingDetail) return;
    if (widget.viewportScale < 0.55) return;

    _detailDebounce?.cancel();
    _detailDebounce = Timer(const Duration(milliseconds: 260), () async {
      if (!mounted || _detail != null || _loadingDetail) return;
      _loadingDetail = true;
      final token = _loadToken;
      final image = await decodeImageCapped(widget.path, widget.maxDecodeEdge);
      if (!mounted || token != _loadToken) {
        image?.dispose();
        return;
      }
      setState(() {
        _detail = image;
        _loadingDetail = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final image = _detail ?? _preview;

    return CustomPaint(
      painter: CheckerboardPainter(light: t.checkerLight, dark: t.checkerDark, cellSize: 12),
      child: image == null
          ? const SizedBox.expand()
          : RawImage(
              image: image,
              width: widget.logicalSize.width,
              height: widget.logicalSize.height,
              fit: BoxFit.fill,
              // 预览阶段用低采样过滤，切到高分辨率后再用高质量过滤。
              filterQuality: _detail != null ? FilterQuality.medium : FilterQuality.low,
            ),
    );
  }
}

/// 按最长边上限解码图像。
///
/// 使用 [ui.ImmutableBuffer.fromFilePath] + [ui.ImageDescriptor]，
/// 让解码器直接从文件流读取并按目标尺寸解码，避免先把整个文件读进内存。
Future<ui.Image?> decodeImageCapped(String path, int maxEdge) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromFilePath(path);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    final longest = math.max(width, height);

    int? targetWidth;
    int? targetHeight;
    if (longest > maxEdge) {
      if (width >= height) {
        targetWidth = maxEdge;
      } else {
        targetHeight = maxEdge;
      }
    }

    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } on Object {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

class _SplitHandle extends StatelessWidget {
  const _SplitHandle({
    required this.position,
    required this.height,
    required this.tokens,
    required this.dragging,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDrag,
  });

  final double position;
  final double height;
  final AppTokens tokens;
  final bool dragging;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position - 22,
      top: 0,
      width: 44,
      height: height,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => onDragStart(),
          onHorizontalDragEnd: (_) => onDragEnd(),
          onHorizontalDragCancel: onDragEnd,
          onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
          child: CustomPaint(
            painter: _SplitHandlePainter(
              color: Colors.white,
              glow: tokens.accent,
              dragging: dragging,
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitHandlePainter extends CustomPainter {
  const _SplitHandlePainter({
    required this.color,
    required this.glow,
    required this.dragging,
  });

  final Color color;
  final Color glow;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = dragging ? 2.4 : 1.6;
    canvas.drawLine(Offset(centerX, 0), Offset(centerX, size.height), linePaint);

    final knobRadius = dragging ? 15.0 : 13.0;
    final knobCenter = Offset(centerX, size.height / 2);
    canvas.drawCircle(
      knobCenter,
      knobRadius + 6,
      Paint()..color = glow.withValues(alpha: dragging ? 0.35 : 0.22),
    );
    canvas.drawCircle(knobCenter, knobRadius, Paint()..color = color);
    canvas.drawCircle(
      knobCenter,
      knobRadius,
      Paint()
        ..color = glow.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // 双向箭头。
    final arrowPaint = Paint()
      ..color = const Color(0xFF1B1E26)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    const dx = 4.5;
    const dy = 3.6;
    canvas.drawLine(knobCenter.translate(-dx, 0), knobCenter.translate(-dx + 2.6, -dy), arrowPaint);
    canvas.drawLine(knobCenter.translate(-dx, 0), knobCenter.translate(-dx + 2.6, dy), arrowPaint);
    canvas.drawLine(knobCenter.translate(dx, 0), knobCenter.translate(dx - 2.6, -dy), arrowPaint);
    canvas.drawLine(knobCenter.translate(dx, 0), knobCenter.translate(dx - 2.6, dy), arrowPaint);
  }

  @override
  bool shouldRepaint(_SplitHandlePainter oldDelegate) =>
      oldDelegate.dragging != dragging || oldDelegate.color != color;
}

class _ZoomReadout extends StatelessWidget {
  const _ZoomReadout({required this.scale, required this.tokens});

  final double scale;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
        decoration: BoxDecoration(
          color: tokens.isDark
              ? Colors.black.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: tokens.border.withValues(alpha: 0.6)),
        ),
        child: Text(
          '${(scale * 100).round()}%',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: tokens.textSecondary,
              ),
        ),
      ),
    );
  }
}
