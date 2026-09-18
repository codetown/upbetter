import 'package:flutter/material.dart';

import '../core/engine/upscale_engine.dart';
import '../core/runtime/runtime_manager.dart';
import '../core/settings.dart';
import 'pages/home_shell.dart';
import 'pages/install_page.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';


/// 把三个长生命周期的对象注入到整棵树。
///
/// 刻意不引入状态管理框架：这几个对象本身就是 [ChangeNotifier] /
/// [ValueNotifier]，配合 [ListenableBuilder] 能做到精确到单个任务的局部重建，
/// 既省去了依赖，也让重建范围完全可控。
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.runtime,
    required this.engine,
    this.startupPaths = const [],
    this.startupAutoStart = false,
    required super.child,
  });

  final AppSettings settings;
  final RuntimeManager runtime;
  final UpscaleEngine engine;
  final List<String> startupPaths;

  /// 导入完成后是否立刻开始处理。
  final bool startupAutoStart;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 未挂载：请确认组件位于 UpbetterApp 之下');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      settings != oldWidget.settings ||
      runtime != oldWidget.runtime ||
      engine != oldWidget.engine;
}

class UpbetterApp extends StatelessWidget {
  const UpbetterApp({
    super.key,
    required this.settings,
    required this.runtime,
    required this.engine,
    this.startupPaths = const [],
    this.startupAutoStart = false,
  });

  final AppSettings settings;
  final RuntimeManager runtime;
  final UpscaleEngine engine;

  /// 命令行传入、等待导入的文件与目录。
  final List<String> startupPaths;

  /// 导入完成后是否立刻开始处理。
  final bool startupAutoStart;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: settings,
      runtime: runtime,
      engine: engine,
      startupPaths: startupPaths,
      startupAutoStart: startupAutoStart,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return MaterialApp(
            title: 'Upbetter',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(AppTokens.light.withAccent(settings.accentSeed)),
            darkTheme: buildAppTheme(AppTokens.dark.withAccent(settings.accentSeed)),
            themeMode: settings.themeMode,
            scrollBehavior: const DesktopScrollBehavior(),
            home: const _Root(),
          );
        },
      ),
    );
  }
}

/// 根据运行时状态在「安装引导」与「主工作区」之间切换。
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final runtime = AppScope.of(context).runtime;
    final tokens = AppTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: ListenableBuilder(
        listenable: runtime,
        builder: (context, _) {
          final ready = runtime.isReady;
          return AnimatedSwitcher(
            duration: Motion.normal,
            switchInCurve: Motion.emphasized,
            switchOutCurve: Motion.exit,
            child: ready
                ? const HomeShell(key: ValueKey('shell'))
                : InstallPage(key: const ValueKey('install')),
          );
        },
      ),
    );
  }
}
