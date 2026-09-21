import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/runtime/runtime_manager.dart';
import '../../core/util/format.dart';
import '../app.dart';
import '../shell/title_bar.dart';
import '../theme/tokens.dart';
import '../util/file_dialogs.dart';
import '../widgets/primitives.dart';

/// 首次启动的引擎安装引导。
///
/// 超分模型与推理引擎体积较大（压缩包约 43 MB），不适合随安装包分发；
/// 这里在首次运行时按需下载，并全程展示可读的进度与来源说明。
class InstallPage extends StatelessWidget {
  const InstallPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final runtime = AppScope.of(context).runtime;

    return Column(
      children: [
        const TitleBar(),
        Expanded(
          child: Stack(
            children: [
              const _BackdropGlow(),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Gap.xxl),
                  child: ListenableBuilder(
                    listenable: runtime,
                    builder: (context, _) => SizedBox(
                      width: 560,
                      child: Panel(
                        padding: const EdgeInsets.all(Gap.xxxl),
                        radius: Radii.xl,
                        child: _body(context, t, runtime),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, AppTokens t, RuntimeManager runtime) {
    switch (runtime.stage) {
      case RuntimeStage.checking:
        return const _CheckingBody();
      case RuntimeStage.downloading:
        return _DownloadingBody(runtime: runtime);
      case RuntimeStage.extracting:
        return const _ExtractingBody();
      case RuntimeStage.error:
        return _ErrorBody(runtime: runtime);
      case RuntimeStage.ready:
        return const _CheckingBody();
      case RuntimeStage.absent:
        return _ReadyToInstallBody(runtime: runtime);
    }
  }
}

class _CheckingBody extends StatelessWidget {
  const _CheckingBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Skeleton(width: 200, height: 22, radius: Radii.sm),
        const SizedBox(height: Gap.lg),
        const Skeleton(width: 340, height: 14, radius: Radii.sm),
        const SizedBox(height: Gap.sm),
        const Skeleton(width: 260, height: 14, radius: Radii.sm),
      ],
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      children: [
        // 这里用真正的应用图标（与 exe 内嵌的是同一份美术资源），
        // 尺寸够大，图标里的文字也能看清。
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: BrandColors.glow.withValues(alpha: 0.34),
                blurRadius: 30,
                spreadRadius: -4,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Image.asset(
            'assets/icon_256.png',
            width: 68,
            height: 68,
            filterQuality: FilterQuality.high,
            // 图标缺失时退回原来的星标，不至于开天窗。
            errorBuilder: (context, _, _) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: t.accentGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Symbols.auto_awesome, size: 32, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),
        Text(
          '欢迎使用 Upbetter',
          style: Theme.of(context).textTheme.displaySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ReadyToInstallBody extends StatelessWidget {
  const _ReadyToInstallBody({required this.runtime});

  final RuntimeManager runtime;

  Future<void> _useExisting(BuildContext context) async {
    final used = await FileDialogs.pickEngineDirectory(context, runtime);
    if (used && runtime.models.value.isEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('引擎已就位，但未找到模型权重，请确认目录下存在 models 文件夹')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Brand(),
        const SizedBox(height: Gap.md),
        Text(
          '还需要一个本地 AI 推理引擎来完成放大。\n它只下载一次，之后完全离线运行。',
          style: text.bodyMedium?.copyWith(color: t.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gap.xxl),
        const _FeatureRow(
          icon: Symbols.bolt,
          title: 'Vulkan GPU 加速',
          detail: '走显卡推理，比 CPU 快数十倍',
        ),
        const _FeatureRow(
          icon: Symbols.lock,
          title: '完全离线',
          detail: '图像不离开你的电脑，无任何上传',
        ),
        const _FeatureRow(
          icon: Symbols.layers,
          title: '内含 3 个模型',
          detail: '通用照片 · 动漫插画 · 极速通用',
        ),
        const SizedBox(height: Gap.xxl),
        GradientButton(
          label: '下载并安装引擎',
          icon: Symbols.download,
          onPressed: () {
            final settings = AppScope.of(context).settings;
            runtime.install(customSource: settings.downloadSource);
          },
        ),
        const SizedBox(height: Gap.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '来自 Real-ESRGAN 官方发行版 · 约 43 MB',
              style: text.labelSmall?.copyWith(color: t.textTertiary),
            ),
            const SizedBox(width: Gap.sm),
            InkWell(
              onTap: runtime.isBusy ? null : () => _useExisting(context),
              borderRadius: Radii.allSm,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '已有引擎？',
                  style: text.labelSmall?.copyWith(
                    color: t.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.accentSoft,
              borderRadius: Radii.allSm,
            ),
            child: Icon(icon, size: 17, color: t.accent),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                Text(detail, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadingBody extends StatelessWidget {
  const _DownloadingBody({required this.runtime});

  final RuntimeManager runtime;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final progress = runtime.progress.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Brand(),
        const SizedBox(height: Gap.xxl),
        Row(
          children: [
            Expanded(
              child: Text('正在下载推理引擎', style: text.titleSmall),
            ),
            Text(
              Fmt.percent(progress, digits: 1),
              style: text.titleSmall?.copyWith(
                color: t.accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: t.surfaceSunken,
          ),
        ),
        const SizedBox(height: Gap.md),
        Row(
          children: [
            Expanded(
              child: Text(
                '${Fmt.bytes(runtime.receivedBytes)} / ${Fmt.bytes(runtime.totalBytes)}',
                style: text.bodySmall,
              ),
            ),
            Text(
              runtime.bytesPerSecond > 0 ? Fmt.byteRate(runtime.bytesPerSecond) : '连接中…',
              style: text.bodySmall?.copyWith(
                color: t.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.xl),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            onPressed: runtime.cancelInstall,
            icon: const Icon(Symbols.close, size: 15),
            label: const Text('取消'),
          ),
        ),
      ],
    );
  }
}

class _ExtractingBody extends StatelessWidget {
  const _ExtractingBody();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
        const SizedBox(height: Gap.xl),
        Text('正在解压模型权重', style: text.titleSmall),
        const SizedBox(height: Gap.sm),
        Text(
          '首次解压需要几秒钟，之后启动都是秒开',
          style: text.bodySmall?.copyWith(color: t.textTertiary),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatefulWidget {
  const _ErrorBody({required this.runtime});

  final RuntimeManager runtime;

  @override
  State<_ErrorBody> createState() => _ErrorBodyState();
}

class _ErrorBodyState extends State<_ErrorBody> {
  late final TextEditingController _source = TextEditingController(
    text: AppScope.of(context).settings.downloadSource,
  );

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    final settings = AppScope.of(context).settings;
    settings.downloadSource = _source.text.trim();
    await widget.runtime.install(force: true, customSource: settings.downloadSource);
  }

  Future<void> _useExisting() async {
    await FileDialogs.pickEngineDirectory(context, widget.runtime);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final runtime = widget.runtime;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: t.danger.withValues(alpha: 0.12),
              borderRadius: Radii.allLg,
              border: Border.all(color: t.danger.withValues(alpha: 0.3)),
            ),
            child: Icon(Symbols.error, size: 24, color: t.danger),
          ),
        ),
        const SizedBox(height: Gap.lg),
        Text('安装未完成', style: text.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: Gap.sm),
        Text(
          runtime.errorMessage ?? '未知错误',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gap.lg),
        Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            color: t.surfaceSunken,
            borderRadius: Radii.allSm,
            border: Border.all(color: t.border),
          ),
          child: Text(
            '下载引擎需要访问 GitHub。应用已自动尝试若干加速镜像，仍失败时'
            '通常是网络环境限制。你可以：设置系统代理后重试、在下方填入可信的镜像地址，'
            '或直接指定本地已有的引擎目录。',
            style: text.bodySmall?.copyWith(color: t.textTertiary, height: 1.5),
          ),
        ),
        const SizedBox(height: Gap.md),
        IconField(
          controller: _source,
          icon: Symbols.link,
          hint: '自定义下载地址（留空则使用内置镜像）',
        ),
        const SizedBox(height: Gap.lg),
        GradientButton(
          label: '重试',
          icon: Symbols.refresh,
          onPressed: _retry,
        ),
        const SizedBox(height: Gap.sm),
        TextButton(
          onPressed: _useExisting,
          child: const Text('已有引擎？手动指定目录'),
        ),
      ],
    );
  }
}

/// 背景光晕。让空白的安装页不至于显得冷清。
class _BackdropGlow extends StatelessWidget {
  const _BackdropGlow();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.45),
            radius: 0.9,
            colors: [
              t.accent.withValues(alpha: t.isDark ? 0.13 : 0.08),
              t.canvas.withValues(alpha: 0),
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
