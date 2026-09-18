import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// 桌面端的滚动行为：允许鼠标拖拽滚动，去掉移动端的 overscroll 光晕。
class DesktopScrollBehavior extends MaterialScrollBehavior {
  const DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics(parent: BouncingScrollPhysics());
}

ThemeData buildAppTheme(AppTokens t) {
  final scheme = ColorScheme(
    brightness: t.brightness,
    primary: t.accent,
    onPrimary: t.accentContrast,
    primaryContainer: t.accentSoft,
    onPrimaryContainer: t.textPrimary,
    secondary: t.accent,
    onSecondary: t.accentContrast,
    surface: t.surface,
    onSurface: t.textPrimary,
    surfaceContainerHighest: t.surfaceElevated,
    onSurfaceVariant: t.textSecondary,
    outline: t.borderStrong,
    outlineVariant: t.border,
    error: t.danger,
    onError: Colors.white,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: t.textPrimary,
    onInverseSurface: t.canvas,
  );

  final text = buildTextTheme(t.textPrimary, t.textSecondary);

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: t.canvas,
    canvasColor: t.canvas,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.compact,
    extensions: [t],
    dividerTheme: DividerThemeData(
      color: t.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: t.textSecondary, size: 18),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 420),
      showDuration: const Duration(seconds: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.isDark ? const Color(0xFF2A3038) : const Color(0xFF2A3038),
        borderRadius: Radii.allSm,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      textStyle: text.labelMedium?.copyWith(color: Colors.white, height: 1.35),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered) ? 10 : 6,
      ),
      radius: const Radius.circular(6),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? t.textTertiary
            : t.borderStrong.withValues(alpha: 0.7),
      ),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.accentContrast,
        disabledBackgroundColor: t.surfaceElevated,
        disabledForegroundColor: t.textTertiary,
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.md),
        textStyle: text.labelLarge,
        shape: const RoundedRectangleBorder(borderRadius: Radii.allMd),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.textPrimary,
        side: BorderSide(color: t.borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        textStyle: text.labelLarge,
        shape: const RoundedRectangleBorder(borderRadius: Radii.allMd),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
        textStyle: text.labelLarge,
        shape: const RoundedRectangleBorder(borderRadius: Radii.allSm),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: t.textSecondary,
        highlightColor: t.accentSoft,
        shape: const RoundedRectangleBorder(borderRadius: Radii.allSm),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accent,
      inactiveTrackColor: t.surfaceSunken,
      thumbColor: t.accent,
      overlayColor: t.accentSoft,
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.white : t.textTertiary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? t.accent : t.surfaceSunken,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? t.accent : t.borderStrong,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      linearTrackColor: t.surfaceSunken,
      circularTrackColor: Colors.transparent,
      linearMinHeight: 4,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: Radii.allXl),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.allMd,
        side: BorderSide(color: t.border),
      ),
      textStyle: text.bodyMedium,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.surfaceElevated),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: Radii.allMd,
            side: BorderSide(color: t.border),
          ),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surfaceSunken,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.md),
      hintStyle: text.bodyMedium?.copyWith(color: t.textTertiary),
      border: OutlineInputBorder(
        borderRadius: Radii.allSm,
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: Radii.allSm,
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: Radii.allSm,
        borderSide: BorderSide(color: t.accent, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: Radii.allSm,
        borderSide: BorderSide(color: t.danger),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surfaceElevated,
      contentTextStyle: text.bodyMedium,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.allMd,
        side: BorderSide(color: t.border),
      ),
    ),
  );
}
