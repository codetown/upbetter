import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/models.dart';
import '../../core/util/format.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../util/system.dart';
import '../widgets/primitives.dart';
import 'log_sheet.dart';

/// 底部状态栏：队列规模、吞吐与全局操作入口。
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.selected});

  final ValueNotifier<UpscaleJob?> selected;

  static const double height = 30;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final scope = AppScope.of(context);
    final engine = scope.engine;

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: ListenableBuilder(
        listenable: engine,
        builder: (context, _) {
          final jobs = engine.jobs;
          final totalPixels = jobs.fold<int>(0, (sum, j) => sum + j.pixelCount);
          final done = engine.completedCount;

          return Row(
            children: [
              _Stat(
                icon: Symbols.photo_library,
                label: jobs.isEmpty
                    ? '等待导入'
                    : '${jobs.length} 个文件 · ${Fmt.megapixels(1, totalPixels)}',
                tokens: t,
              ),
              if (done > 0) ...[
                const _Sep(),
                _Stat(
                  icon: Symbols.done_all,
                  label: '已完成 $done',
                  tokens: t,
                  color: t.success,
                ),
              ],
              const Spacer(),
              ValueListenableBuilder<double>(
                valueListenable: engine.throughput,
                builder: (context, throughput, _) {
                  if (throughput <= 0) return const SizedBox.shrink();
                  return Row(
                    children: [
                      _Stat(
                        icon: Symbols.speed,
                        label: '${(throughput / 1e6).toStringAsFixed(2)} MP/s',
                        tokens: t,
                      ),
                      const _Sep(),
                    ],
                  );
                },
              ),
              IconBtn(
                icon: Symbols.folder_open,
                tooltip: '打开输出目录',
                size: 24,
                iconSize: 15,
                onPressed: () async {
                  final custom = scope.settings.options.outputDir;
                  final job = selected.value ?? (jobs.isEmpty ? null : jobs.first);
                  final dir = switch (scope.settings.options.location) {
                    OutputLocation.custom when custom != null => custom,
                    OutputLocation.subfolder when job != null =>
                      '${job.inputDir}\\${scope.settings.options.subfolderName}',
                    _ when job != null => job.inputDir,
                    _ => null,
                  };
                  if (dir != null) await SystemShell.openDirectory(dir);
                },
              ),
              IconBtn(
                icon: Symbols.description,
                tooltip: '查看运行日志',
                size: 24,
                iconSize: 15,
                onPressed: () => LogSheet.show(context),
              ),
              _AccentPicker(tokens: t),
              _ThemeToggle(tokens: t),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.tokens,
    this.color,
  });

  final IconData icon;
  final String label;
  final AppTokens tokens;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? tokens.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c)),
      ],
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: Gap.md),
      color: AppTokens.of(context).border,
    );
  }
}

/// 强调色选择器。整个界面的重音色都从这里派生。
class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.tokens});

  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;

    return PopupMenuButton<int>(
      tooltip: '强调色',
      padding: EdgeInsets.zero,
      splashRadius: 16,
      icon: Icon(Symbols.palette, size: 15, color: tokens.textSecondary),
      itemBuilder: (context) => [
        PopupMenuItem<int>(
          // 保持 enabled，否则内部的手势无法响应；
          // 色块自己会消费点击事件，不会顺带把菜单关掉。
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('强调色', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: Gap.md),
              Wrap(
                spacing: Gap.md,
                runSpacing: Gap.md,
                children: [
                  for (final choice in kAccentChoices)
                    _AccentSwatch(
                      choice: choice,
                      selected: settings.accentSeed == choice.seed,
                      onTap: () {
                        settings.accentSeed = choice.seed;
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final AccentChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Tooltip(
      message: choice.name,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: choice.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? t.textPrimary : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(Symbols.check, size: 14, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.tokens});

  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final mode = settings.themeMode;
    final isDark = tokens.isDark;

    return IconBtn(
      icon: switch (mode) {
        ThemeMode.system => Symbols.contrast,
        ThemeMode.light => Symbols.light_mode,
        ThemeMode.dark => Symbols.dark_mode,
      },
      tooltip: switch (mode) {
        ThemeMode.system => '跟随系统（点击切换为深色）',
        ThemeMode.dark => '深色（点击切换为浅色）',
        ThemeMode.light => '浅色（点击跟随系统）',
      },
      size: 24,
      iconSize: 15,
      active: isDark,
      onPressed: () {
        settings.themeMode = switch (mode) {
          ThemeMode.system => ThemeMode.dark,
          ThemeMode.dark => ThemeMode.light,
          ThemeMode.light => ThemeMode.system,
        };
      },
    );
  }
}
