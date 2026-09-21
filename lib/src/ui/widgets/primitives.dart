import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.border,
  });

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? t.surface.withValues(alpha: 0.78),
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 基础面板：一块带描边的表面。
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.borderColor,
    this.radius = Radii.lg,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final Radius radius;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (elevated ? t.surfaceElevated : t.surface),
        borderRadius: BorderRadius.all(radius),
        border: Border.all(color: borderColor ?? t.border),
      ),
      child: child,
    );
  }
}

/// 分区小标题。使用大写字母间距，在密集的工具界面里提供清晰的分层。
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: t.textTertiary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 紧凑的图标按钮。
class IconBtn extends StatelessWidget {
  const IconBtn({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 32,
    this.iconSize = 18,
    this.color,
    this.active = false,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? color;
  final bool active;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final enabled = onPressed != null;

    final effectiveColor = !enabled
        ? t.textTertiary.withValues(alpha: 0.5)
        : active
        ? t.accent
        : (color ?? t.textSecondary);

    Widget button = Material(
      color: filled || active ? t.accentSoft : Colors.transparent,
      borderRadius: Radii.allSm,
      child: InkWell(
        onTap: onPressed,
        borderRadius: Radii.allSm,
        hoverColor: t.isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.04),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: effectiveColor),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// 分段控件。选中项用一层会滑动的胶囊高亮，比 Material 的 ToggleButtons 更轻快。
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expand = true,
  });

  final List<Segment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final index = segments.indexWhere((s) => s.value == value);
    final safeIndex = index < 0 ? 0 : index;

    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (var i = 0; i < segments.length; i++)
          if (expand)
            Expanded(
              child: _buildItem(context, t, segments[i], i == safeIndex),
            )
          else
            _buildItem(context, t, segments[i], i == safeIndex),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surfaceSunken.withValues(alpha: 0.42),
        borderRadius: Radii.allMd,
        border: Border.all(color: t.border),
      ),
      child: row,
    );
  }

  Widget _buildItem(
    BuildContext context,
    AppTokens t,
    Segment<T> segment,
    bool selected,
  ) {
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.standard,
      decoration: BoxDecoration(
        color: selected ? t.accent : Colors.transparent,
        borderRadius: Radii.allSm,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: segment.enabled && !selected
              ? () => onChanged(segment.value)
              : null,
          borderRadius: Radii.allSm,
          hoverColor: selected ? Colors.transparent : t.accentSoft,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  segment.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: !segment.enabled
                        ? t.textTertiary.withValues(alpha: 0.5)
                        : selected
                        ? t.accentContrast
                        : t.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (segment.caption != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    segment.caption!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: selected
                          ? t.accentContrast.withValues(alpha: 0.8)
                          : t.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Segment<T> {
  const Segment(this.value, this.label, {this.caption, this.enabled = true});

  final T value;
  final String label;
  final String? caption;
  final bool enabled;
}

/// 主操作按钮：带渐变与轻微内发光，是整个界面唯一的「重」视觉元素。
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.height = 46,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final double height;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final enabled = widget.onPressed != null && !widget.busy;

    final decoration = BoxDecoration(
      gradient: LinearGradient(
        colors: enabled
            ? t.accentGradient
            : [t.surfaceElevated, t.surfaceElevated],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderRadius: Radii.allMd,
      boxShadow: enabled && _hovered
          ? [
              BoxShadow(
                color: t.accent.withValues(alpha: 0.35),
                blurRadius: 20,
                spreadRadius: -2,
                offset: const Offset(0, 4),
              ),
            ]
          : const [],
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: Motion.instant,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.standard,
            height: widget.height,
            decoration: decoration,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.busy)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else if (widget.icon != null)
                    Icon(
                      widget.icon,
                      size: 18,
                      color: enabled ? Colors.white : t.textTertiary,
                    ),
                  if (widget.busy || widget.icon != null)
                    const SizedBox(width: Gap.sm),
                  Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: enabled ? Colors.white : t.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 小型状态徽标。取名刻意避开 Material 自带的 `Badge`，防止导入冲突。
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : Gap.sm,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: dense ? 10 : 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// 键值对展示行，用于「输出尺寸」「预计耗时」这类只读信息。
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: t.textTertiary),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(label, style: text.bodySmall)),
          Text(
            value,
            style: text.bodySmall?.copyWith(
              color: valueColor ?? t.textPrimary,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片式可选项。用于模型选择——比下拉菜单更能表达每个模型的差异。
class SelectableCard extends StatefulWidget {
  const SelectableCard({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.md),
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<SelectableCard> createState() => _SelectableCardState();
}

class _SelectableCardState extends State<SelectableCard> {
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
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.selected
                ? t.accentSoft
                : _hovered
                ? t.surfaceElevated.withValues(alpha: 0.45)
                : Colors.transparent,
            borderRadius: Radii.allMd,
            border: Border.all(
              color: widget.selected
                  ? t.accent.withValues(alpha: 0.55)
                  : _hovered
                  ? t.borderStrong
                  : t.border,
              width: widget.selected ? 1.4 : 1,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 透明的棋盘格背景，用于展示带 alpha 通道的图像。
class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter({
    required this.light,
    required this.dark,
    this.cellSize = 10,
  });

  final Color light;
  final Color dark;
  final double cellSize;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = dark);
    final lightPaint = Paint()..color = light;
    final cols = (size.width / cellSize).ceil();
    final rows = (size.height / cellSize).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if ((x + y).isEven) continue;
        canvas.drawRect(
          Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize),
          lightPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CheckerboardPainter oldDelegate) =>
      light != oldDelegate.light ||
      dark != oldDelegate.dark ||
      cellSize != oldDelegate.cellSize;
}

/// 空状态占位。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: t.surfaceElevated,
                borderRadius: Radii.allLg,
                border: Border.all(color: t.border),
              ),
              child: Icon(icon, size: 28, color: t.textTertiary),
            ),
            const SizedBox(height: Gap.lg),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: Gap.sm),
            Text(message, style: text.bodySmall, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: Gap.xl), action!],
          ],
        ),
      ),
    );
  }
}

/// 加载骨架块。
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = Radii.sm,
  });

  final double width;
  final double height;
  final Radius radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final v = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.all(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - v), 0),
              end: Alignment(1 - 2 * (1 - v), 0),
              colors: [
                t.surfaceElevated,
                t.border.withValues(alpha: 0.6),
                t.surfaceElevated,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// 带说明文字的开关行。
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.bodyMedium),
              const SizedBox(height: 1),
              Text(
                detail,
                style: text.labelSmall?.copyWith(color: t.textTertiary),
              ),
            ],
          ),
        ),
        Transform.scale(
          scale: 0.82,
          child: Switch(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

/// 带前缀图标的输入框。
class IconField extends StatelessWidget {
  const IconField({
    super.key,
    required this.controller,
    required this.icon,
    this.hint,
    this.onChanged,
    this.trailing,
  });

  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 16, color: t.textTertiary),
        prefixIconConstraints: const BoxConstraints(minWidth: 34),
        suffixIcon: trailing,
      ),
    );
  }
}
