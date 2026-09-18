import 'package:flutter/material.dart';

/// 应用的设计令牌。
///
/// 通过 [ThemeExtension] 挂载，因此任何组件都能用
/// `Theme.of(context).extension<AppTokens>()!` 取到，无需全局单例。
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSoft,
    required this.accentContrast,
    required this.accentGradient,
    required this.success,
    required this.warning,
    required this.danger,
    required this.overlay,
    required this.checkerLight,
    required this.checkerDark,
  });

  final Brightness brightness;

  /// 应用背景（最底层）。
  final Color canvas;

  /// 面板背景。
  final Color surface;

  /// 悬浮/选中态面板。
  final Color surfaceElevated;

  /// 凹陷区域，如输入框、进度槽。
  final Color surfaceSunken;

  final Color border;
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color accent;
  final Color accentSoft;
  final Color accentContrast;
  final List<Color> accentGradient;

  final Color success;
  final Color warning;
  final Color danger;

  /// 全屏遮罩（拖放提示层）。
  final Color overlay;

  /// 透明背景棋盘格。
  final Color checkerLight;
  final Color checkerDark;

  bool get isDark => brightness == Brightness.dark;

  static const AppTokens dark = AppTokens(
    brightness: Brightness.dark,
    canvas: Color(0xFF0A0B0F),
    surface: Color(0xFF111319),
    surfaceElevated: Color(0xFF181B23),
    surfaceSunken: Color(0xFF0D0F14),
    border: Color(0xFF232833),
    borderStrong: Color(0xFF323949),
    textPrimary: Color(0xFFF3F5F9),
    textSecondary: Color(0xFF99A2B3),
    textTertiary: Color(0xFF626B7C),
    accent: Color(0xFF7C6BFF),
    accentSoft: Color(0x267C6BFF),
    accentContrast: Color(0xFFFFFFFF),
    accentGradient: [Color(0xFF8B7BFF), Color(0xFF4FC3F7)],
    success: Color(0xFF3DDC97),
    warning: Color(0xFFFFC65C),
    danger: Color(0xFFFF6B6B),
    overlay: Color(0xE60A0B0F),
    checkerLight: Color(0xFF262B36),
    checkerDark: Color(0xFF1A1E26),
  );

  static const AppTokens light = AppTokens(
    brightness: Brightness.light,
    canvas: Color(0xFFF4F5F8),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF7F8FB),
    surfaceSunken: Color(0xFFEDEFF4),
    border: Color(0xFFE2E5EC),
    borderStrong: Color(0xFFCBD1DC),
    textPrimary: Color(0xFF111420),
    textSecondary: Color(0xFF5A6474),
    textTertiary: Color(0xFF8B93A3),
    accent: Color(0xFF5B4BE0),
    accentSoft: Color(0x1F5B4BE0),
    accentContrast: Color(0xFFFFFFFF),
    accentGradient: [Color(0xFF6D5EF8), Color(0xFF2196F3)],
    success: Color(0xFF12A66A),
    warning: Color(0xFFD98A00),
    danger: Color(0xFFE03B3B),
    overlay: Color(0xE6F4F5F8),
    checkerLight: Color(0xFFDDE1E8),
    checkerDark: Color(0xFFC7CCD6),
  );

  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>() ?? dark;

  /// 按用户选择的强调色重新着色。
  ///
  /// 渐变不是写死的，而是由色相旋转推导出来的：这样任意颜色都能得到一个
  /// 协调的搭配，用户不必从有限的预设里挑。浅色主题下整体压暗一点，
  /// 否则亮色在白色背景上对比度不足。
  AppTokens withAccent(int seed) {
    final isLight = brightness == Brightness.light;
    final base = Color(seed);
    final hsl = HSLColor.fromColor(base);

    Color shift(double hueDelta, double lightnessDelta) => hsl
        .withHue((hsl.hue + hueDelta) % 360)
        .withLightness((hsl.lightness + lightnessDelta).clamp(0.0, 1.0))
        .toColor();

    final accent = isLight ? shift(0, -0.1) : base;

    return copyWith(
      accent: accent,
      accentSoft: accent.withValues(alpha: isLight ? 0.12 : 0.16),
      accentContrast: const Color(0xFFFFFFFF),
      accentGradient: [
        isLight ? accent : shift(0, 0.1),
        shift(32, isLight ? -0.02 : 0.06),
      ],
    );
  }

  @override
  AppTokens copyWith({
    Brightness? brightness,
    Color? canvas,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceSunken,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentSoft,
    Color? accentContrast,
    List<Color>? accentGradient,
    Color? success,
    Color? warning,
    Color? danger,
    Color? overlay,
    Color? checkerLight,
    Color? checkerDark,
  }) {
    return AppTokens(
      brightness: brightness ?? this.brightness,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentContrast: accentContrast ?? this.accentContrast,
      accentGradient: accentGradient ?? this.accentGradient,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      overlay: overlay ?? this.overlay,
      checkerLight: checkerLight ?? this.checkerLight,
      checkerDark: checkerDark ?? this.checkerDark,
    );
  }

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceElevated: c(surfaceElevated, other.surfaceElevated),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      accentContrast: c(accentContrast, other.accentContrast),
      accentGradient: [
        c(accentGradient.first, other.accentGradient.first),
        c(accentGradient.last, other.accentGradient.last),
      ],
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      overlay: c(overlay, other.overlay),
      checkerLight: c(checkerLight, other.checkerLight),
      checkerDark: c(checkerDark, other.checkerDark),
    );
  }
}

/// 品牌色。取自应用图标，**不随强调色变化**——应用图标是固定的，
/// 界面里代表「应用本身」的元素就应该跟它保持一致，
/// 否则用户换成绿色强调色后，标题栏的标识会跟任务栏图标对不上。
class BrandColors {
  BrandColors._();

  /// 图标主体蓝（取自图标的深色端，并调整到适合承载白色文字的明度）。
  static const Color base = Color(0xFF2563EB);

  /// 图标高光青（取自图标右上角的亮部），用于渐变终点与发光。
  static const Color glow = Color(0xFF38BDF8);

  static const List<Color> gradient = [base, glow];
}

/// 可选的强调色。只给出基准色，渐变由 [AppTokens.withAccent] 推导。
class AccentChoice {
  const AccentChoice(this.seed, this.name);

  final int seed;
  final String name;

  Color get color => Color(seed);
}

const List<AccentChoice> kAccentChoices = [
  // 默认项与应用图标同色，保证开箱即用的视觉是统一的。
  AccentChoice(0xFF2563EB, '品牌蓝'),
  AccentChoice(0xFF7C6BFF, '星紫'),
  AccentChoice(0xFF10B981, '薄荷'),
  AccentChoice(0xFFF59E0B, '琥珀'),
  AccentChoice(0xFFEC4899, '品红'),
  AccentChoice(0xFF64748B, '石墨'),
];

/// 间距节奏。所有留白都取自这个 4pt 网格，保证视觉一致性。
class Gap {
  Gap._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

class Radii {
  Radii._();

  static const Radius sm = Radius.circular(6);
  static const Radius md = Radius.circular(10);
  static const Radius lg = Radius.circular(14);
  static const Radius xl = Radius.circular(18);

  static const BorderRadius allSm = BorderRadius.all(sm);
  static const BorderRadius allMd = BorderRadius.all(md);
  static const BorderRadius allLg = BorderRadius.all(lg);
  static const BorderRadius allXl = BorderRadius.all(xl);
}

/// 动效时长。桌面端应当比移动端更「快」，避免操作有拖沓感。
class Motion {
  Motion._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 340);

  /// 标准缓动：起步快、收尾稳，是桌面 UI 最讨喜的手感。
  static const Curve standard = Cubic(0.2, 0, 0, 1);
  static const Curve emphasized = Cubic(0.16, 1, 0.3, 1);
  static const Curve exit = Cubic(0.4, 0, 1, 1);
}

/// 平台相关的字体栈。中文回退到系统自带的高质量黑体。
const String _fontStack = 'Segoe UI Variable Text';
const List<String> _fontFallback = [
  'Segoe UI',
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans SC',
  'sans-serif',
];

TextTheme buildTextTheme(Color primary, Color secondary) {
  TextStyle base(double size, FontWeight weight, {Color? color, double? height, double? spacing}) {
    return TextStyle(
      fontFamily: _fontStack,
      fontFamilyFallback: _fontFallback,
      fontSize: size,
      fontWeight: weight,
      color: color ?? primary,
      height: height,
      letterSpacing: spacing,
    );
  }

  return TextTheme(
    displaySmall: base(30, FontWeight.w600, height: 1.15, spacing: -0.6),
    headlineMedium: base(24, FontWeight.w600, height: 1.2, spacing: -0.4),
    headlineSmall: base(19, FontWeight.w600, height: 1.25, spacing: -0.2),
    titleLarge: base(16, FontWeight.w600, height: 1.3, spacing: -0.1),
    titleMedium: base(14, FontWeight.w600, height: 1.35),
    titleSmall: base(13, FontWeight.w600, height: 1.35),
    bodyLarge: base(14, FontWeight.w400, height: 1.45),
    bodyMedium: base(13, FontWeight.w400, height: 1.45),
    bodySmall: base(12, FontWeight.w400, height: 1.4, color: secondary),
    labelLarge: base(13, FontWeight.w500, height: 1.2),
    labelMedium: base(12, FontWeight.w500, height: 1.2, color: secondary),
    labelSmall: base(11, FontWeight.w500, height: 1.2, color: secondary, spacing: 0.2),
  );
}
