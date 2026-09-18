import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/core/app_paths.dart';
import 'src/core/engine/upscale_engine.dart';
import 'src/core/runtime/runtime_manager.dart';
import 'src/core/settings.dart';
import 'src/core/util/log.dart';
import 'src/ui/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 这些初始化都只是微秒级的文件系统操作，放在首帧之前完成，
  // 可以让界面一出现就是「就绪」状态，避免闪现加载占位。
  await AppPaths.init();
  Log.initFile();
  Log.i('App', 'Upbetter 启动');

  final settings = await AppSettings.load();
  final runtime = RuntimeManager();
  final engine = UpscaleEngine(runtime: runtime, settings: settings);

  // 只是几个文件存在性检查加上一次小目录扫描，耗时在毫秒级。
  // 提前做完可以让首帧直接呈现正确状态，避免闪现「检测中」。
  await runtime.refresh();

  await windowManager.ensureInitialized();
  // 拦截关闭事件，先把窗口状态落盘再真正退出。
  await windowManager.setPreventClose(true);

  final bounds = settings.windowBounds;
  final options = WindowOptions(
    size: bounds?.size ?? const Size(1480, 920),
    minimumSize: const Size(1040, 680),
    center: bounds == null,
    title: 'Upbetter',
    // 自绘标题栏：这样才能做出与整体设计语言一致的窗口外观。
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    backgroundColor: const Color(0xFF0A0B0F),
  );

  _WindowStateKeeper(settings).attach();

  unawaited(
    windowManager.waitUntilReadyToShow(options, () async {
      if (bounds != null && !settings.windowMaximized) {
        await windowManager.setBounds(bounds);
      }
      await windowManager.show();
      await windowManager.focus();
      if (settings.windowMaximized) await windowManager.maximize();
    }),
  );

  runApp(UpbetterApp(
    settings: settings,
    runtime: runtime,
    engine: engine,
    startupPaths: _parseStartupPaths(args),
    startupAutoStart: args.contains('--run') || args.contains('-r'),
  ));

  // GPU 探测要真正跑一次极短的推理（ncnn 只在初始化时才枚举设备），
  // 因此推迟到首帧之后再执行，避免和界面首绘抢资源。
  if (runtime.isReady) {
    Future<void>.delayed(const Duration(seconds: 2), runtime.detectGpus);
  }
}

/// 解析命令行传入的文件与目录。
///
/// 支持 `upbetter.exe <路径...>` 以及 `--add <路径>` 两种写法，
/// 前者可以直接配合系统的「打开方式」使用；加上 `--run` 则在导入后立即开始处理，
/// 便于脚本化调用。
List<String> _parseStartupPaths(List<String> args) {
  final paths = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--add' || arg == '-a') {
      if (i + 1 < args.length) paths.add(args[++i]);
      continue;
    }
    if (arg.startsWith('-')) continue;
    paths.add(arg);
  }
  return paths;
}

/// 记住窗口的位置、尺寸与最大化状态，下次打开时原样还原。
class _WindowStateKeeper extends WindowListener {
  _WindowStateKeeper(this.settings);

  final AppSettings settings;
  Timer? _debounce;
  bool _closing = false;

  void attach() => windowManager.addListener(this);

  void _captureSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (await windowManager.isMaximized() || await windowManager.isMinimized()) return;
      settings.windowBounds = await windowManager.getBounds();
    });
  }

  @override
  void onWindowResized() => _captureSoon();

  @override
  void onWindowMoved() => _captureSoon();

  @override
  void onWindowMaximize() => settings.windowMaximized = true;

  @override
  void onWindowUnmaximize() => settings.windowMaximized = false;

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    _debounce?.cancel();
    try {
      final maximized = await windowManager.isMaximized();
      settings.windowMaximized = maximized;
      if (!maximized) {
        settings.windowBounds = await windowManager.getBounds();
      }
      await settings.flush();
    } on Object catch (error) {
      Log.w('App', '退出前保存状态失败：$error');
    } finally {
      await _guard(Log.dispose);
      await windowManager.destroy();
    }
  }
}

/// 收尾动作不应阻止窗口退出，失败也要继续。
Future<void> _guard(Future<void> Function() action) async {
  try {
    await action();
  } on Object {
    // ignore
  }
}
