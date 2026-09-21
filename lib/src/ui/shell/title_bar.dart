import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/engine/upscale_engine.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../widgets/primitives.dart';

/// 自绘标题栏。
///
/// 系统标题栏会打断整体视觉语言，而且无法承载「当前 GPU」这类
/// 需要常驻可见的状态信息，因此完全自绘。
class TitleBar extends StatelessWidget {
  const TitleBar({super.key, this.height = defaultHeight});

  static const double defaultHeight = 42;

  final double height;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final engine = AppScope.of(context).engine;

    return GlassSurface(
      height: height,
      border: Border(bottom: BorderSide(color: t.border)),
      child: Row(
        children: [
          const SizedBox(width: Gap.md),
          const _AppMark(),
          const SizedBox(width: Gap.md),
          Expanded(
            child: DragToMoveArea(
              child: SizedBox(
                height: height,
                child: Row(
                  children: [
                    Text(
                      'Upbetter',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                          ),
                    ),
                    const SizedBox(width: Gap.md),
                    // 处理中时在标题栏显示当前文件，让用户切到别的窗口后
                    // 也能一眼看到进度，而不必切回来。
                    Expanded(child: _ActivityIndicator(engine: engine)),
                  ],
                ),
              ),
            ),
          ),
          const _GpuChip(),
          const SizedBox(width: Gap.sm),
          const _WindowControls(),
          const SizedBox(width: Gap.xs),
        ],
      ),
    );
  }
}

/// 标题栏上的应用标识。
///
/// 刻意用简化图形（蓝色圆角方块 + 星芒）而不是缩小的应用图标：
/// 图标里含有 "upbetter" 字样，缩到 22px 会糊成一团，看起来像渲染错误。
/// 这里保留图标的配色与星芒元素，保证与任务栏图标在气质上一致。
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: BrandColors.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Symbols.auto_awesome, size: 13, color: Colors.white),
    );
  }
}

class _ActivityIndicator extends StatelessWidget {
  const _ActivityIndicator({required this.engine});

  final UpscaleEngine engine;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ValueListenableBuilder<QueueState>(
      valueListenable: engine.state,
      builder: (context, state, _) {
        if (state == QueueState.idle) return const SizedBox.shrink();
        return ValueListenableBuilder<String?>(
          valueListenable: engine.currentFileName,
          builder: (context, name, _) {
            return Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: state == QueueState.stopping ? t.warning : t.accent,
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Flexible(
                  child: Text(
                    state == QueueState.stopping ? '正在停止…' : (name ?? '准备中…'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// 显示检测到的 Vulkan 设备。推理引擎的硬件加速能力是这个工具的核心，
/// 把它放在标题栏可以让用户随时确认加速是否生效。
class _GpuChip extends StatelessWidget {
  const _GpuChip();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final runtime = AppScope.of(context).runtime;

    return ValueListenableBuilder(
      valueListenable: runtime.gpus,
      builder: (context, gpus, _) {
        final hasGpu = gpus.isNotEmpty;
        final label = hasGpu ? gpus.first.name : '未检测到 GPU';
        return Tooltip(
          message: hasGpu
              ? 'Vulkan 加速已启用：${gpus.map((g) => '${g.index} · ${g.name}').join('\n')}'
              : '尚未检测到 Vulkan 设备，将回退到 CPU 推理（速度会明显变慢）',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 4),
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.memory,
                  size: 12,
                  color: hasGpu ? t.success : t.warning,
                ),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: t.textSecondary,
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlButton(
          icon: Symbols.remove,
          tooltip: '最小化',
          onTap: windowManager.minimize,
          tokens: t,
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _maximizedNotifier,
          builder: (context, maximized, _) {
            return _ControlButton(
              icon: maximized ? Symbols.filter_none : Symbols.crop_square,
              tooltip: maximized ? '还原' : '最大化',
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              tokens: t,
            );
          },
        ),
        _ControlButton(
          icon: Symbols.close,
          tooltip: '关闭',
          onTap: windowManager.close,
          tokens: t,
          danger: true,
        ),
      ],
    );
  }
}

/// 最大化状态需要被按钮订阅。用全局 notifier 避免每个用到的地方各注册一次监听。
final ValueNotifier<bool> _maximizedNotifier = _MaximizedNotifier();

class _MaximizedNotifier extends ValueNotifier<bool> with WindowListener {
  _MaximizedNotifier() : super(false) {
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (!disposed) value = v;
    });
  }

  bool disposed = false;

  @override
  void onWindowMaximize() => value = true;

  @override
  void onWindowUnmaximize() => value = false;

  @override
  void dispose() {
    disposed = true;
    windowManager.removeListener(this);
    super.dispose();
  }
}

class _ControlButton extends StatefulWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.tokens,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final AppTokens tokens;
  final bool danger;

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final hoverColor = widget.danger
        ? const Color(0xFFE5484D)
        : (t.isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.05));

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Motion.instant,
            width: 40,
            height: 30,
            decoration: BoxDecoration(
              color: _hovered ? hoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: _hovered && widget.danger ? Colors.white : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
