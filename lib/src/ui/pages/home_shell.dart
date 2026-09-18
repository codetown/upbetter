import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
// Flutter 自身也有一个 `ImageInfo`（解码后的图像帧），与这里的图像元信息同名，
// 显式隐藏以免歧义。
import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/engine/upscale_engine.dart';
import '../../core/image/image_probe.dart';
import '../../core/models.dart';
import '../../core/util/log.dart';
import '../app.dart';
import '../panels/preview_panel.dart';
import '../panels/queue_panel.dart';
import '../panels/settings_panel.dart';
import '../panels/status_bar.dart';
import '../shell/title_bar.dart';
import '../theme/tokens.dart';
import '../util/file_dialogs.dart';

/// 主工作区：左侧队列、中间预览、右侧参数。
///
/// 三栏布局让「选图 → 调参 → 看结果」形成一条不需要切换页面的直线，
/// 这是批量处理工具最重要的效率来源。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// 当前在预览区展示的任务。
  final ValueNotifier<UpscaleJob?> selected = ValueNotifier(null);

  bool _dragging = false;
  bool _importing = false;
  bool _startupPathsConsumed = false;

  @override
  void initState() {
    super.initState();
    // 命令行传入的路径要等首帧之后再导入：此时 InheritedWidget 才可安全读取，
    // 而且用户能先看到界面出现，而不是对着空白窗口等待。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _startupPathsConsumed) return;
      _startupPathsConsumed = true;

      final scope = AppScope.of(context);
      if (scope.startupPaths.isEmpty) return;

      await _importPaths(scope.startupPaths);
      if (scope.startupAutoStart && mounted) scope.engine.start();
    });
  }

  @override
  void dispose() {
    selected.dispose();
    super.dispose();
  }

  UpscaleEngine get _engine => AppScope.of(context).engine;

  // ── 导入 ────────────────────────────────────────────────────────────────

  Future<void> _importPaths(Iterable<String> paths) async {
    if (_importing) return;

    // 在第一个 await 之前把所有依赖 context 的东西取出来。
    final scope = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final engine = scope.engine;
    final options = scope.settings.options;

    setState(() => _importing = true);
    try {
      final files = await FileDialogs.collectImages(paths);
      if (files.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('没有找到受支持的图像文件')),
        );
        return;
      }

      // 并发探测文件头。限制并发数，避免一次打开上千个文件句柄。
      final infos = await _probeAll(files);
      final jobs = <UpscaleJob>[];
      var skipped = 0;
      for (var i = 0; i < files.length; i++) {
        final info = infos[i];
        if (info == null) {
          skipped++;
          continue;
        }
        jobs.add(engine.createJob(
          inputPath: files[i],
          sourceInfo: info,
          options: options,
        ));
      }

      engine.addJobs(jobs);
      if (selected.value == null && jobs.isNotEmpty) {
        selected.value = jobs.first;
      }

      final message = StringBuffer('已加入 ${jobs.length} 个文件');
      if (skipped > 0) message.write('，跳过 $skipped 个无法识别的文件');
      messenger.showSnackBar(
        SnackBar(
          content: Text(message.toString()),
          duration: const Duration(seconds: 2),
        ),
      );
    } on Object catch (error, stack) {
      Log.e('Shell', '导入失败', error, stack);
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$error')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 并行探测，但限制在 16 路以内——再高只会争抢磁盘队列，并不会更快。
  static Future<List<ImageInfo?>> _probeAll(List<String> paths) async {
    const concurrency = 16;
    final results = List<ImageInfo?>.filled(paths.length, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= paths.length) return;
        results[index] = await ImageProbe.probe(paths[index]);
      }
    }

    await Future.wait(
      List.generate(concurrency < paths.length ? concurrency : paths.length, (_) => worker()),
    );
    return results;
  }

  Future<void> _pickFiles() async {
    final paths = await FileDialogs.pickImages();
    if (paths.isNotEmpty) await _importPaths(paths);
  }

  Future<void> _pickFolder() async {
    final dir = await FileDialogs.pickDirectory(confirmButtonText: '导入此文件夹');
    if (dir != null) await _importPaths([dir]);
  }

  // ── 快捷键 ──────────────────────────────────────────────────────────────

  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    return {
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): _pickFiles,
      const SingleActivator(LogicalKeyboardKey.keyO, control: true, shift: true): _pickFolder,
      const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
        final engine = _engine;
        if (engine.isRunning) {
          engine.stop();
        } else {
          engine.start();
        }
      },
      const SingleActivator(LogicalKeyboardKey.escape): () {
        final engine = _engine;
        if (engine.isRunning) {
          engine.stop();
        } else {
          selected.value = null;
        }
      },
      const SingleActivator(LogicalKeyboardKey.delete): () {
        final job = selected.value;
        if (job == null) return;
        selected.value = null;
        _engine.removeJob(job);
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);

    return CallbackShortcuts(
      bindings: _shortcuts(),
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (detail) {
            setState(() => _dragging = false);
            _importPaths(detail.files.map((f) => f.path).toList());
          },
          child: Stack(
            children: [
              Column(
                children: [
                  const TitleBar(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        QueuePanel(selected: selected, onPickFiles: _pickFiles, onPickFolder: _pickFolder),
                        _VerticalDivider(color: t.border),
                        Expanded(child: PreviewPanel(selected: selected)),
                        _VerticalDivider(color: t.border),
                        SettingsPanel(selected: selected),
                      ],
                    ),
                  ),
                  StatusBar(selected: selected),
                ],
              ),
              _DropOverlay(visible: _dragging),
              if (_importing)
                Positioned(
                  top: Gap.lg + 42,
                  left: 0,
                  right: 0,
                  child: Center(child: _ImportBanner()),
                ),
              // 让引擎的状态变化驱动状态栏刷新。
              const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(width: 1, color: color);
}

class _ImportBanner extends StatelessWidget {
  const _ImportBanner();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: Radii.allMd,
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: Gap.md),
          Text('正在读取图像信息…', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// 拖放提示遮罩。用明显的视觉反馈告诉用户「松手就会加入队列」。
class _DropOverlay extends StatelessWidget {
  const _DropOverlay({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Motion.fast,
        curve: Motion.standard,
        child: Container(
          color: t.overlay,
          child: Center(
            child: Container(
              width: 420,
              padding: const EdgeInsets.symmetric(horizontal: Gap.xxxl, vertical: Gap.xxl),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: Radii.allXl,
                border: Border.all(color: t.accent.withValues(alpha: 0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.2),
                    blurRadius: 40,
                    spreadRadius: -6,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: t.accentGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Symbols.add_photo_alternate, size: 28, color: Colors.white),
                  ),
                  const SizedBox(height: Gap.lg),
                  Text('松手即可加入队列', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: Gap.sm),
                  Text(
                    '支持 PNG · JPEG · WebP · BMP · GIF · TGA\n也可以直接拖入整个文件夹',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
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
