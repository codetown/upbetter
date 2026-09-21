import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

import '../../core/engine/output_path.dart';
import '../../core/models.dart';
import '../../core/util/format.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../util/file_dialogs.dart';
import '../widgets/primitives.dart';

/// 输出相关的参数：格式、位置、命名与覆盖策略。
class OutputSettingsSection extends StatefulWidget {
  const OutputSettingsSection({
    super.key,
    required this.options,
    required this.onChanged,
  });

  final UpscaleOptions options;
  final ValueChanged<UpscaleOptions> onChanged;

  @override
  State<OutputSettingsSection> createState() => _OutputSettingsSectionState();
}

class _OutputSettingsSectionState extends State<OutputSettingsSection> {
  late final TextEditingController _template = TextEditingController(
    text: widget.options.namingTemplate,
  );
  late final TextEditingController _subfolder = TextEditingController(
    text: widget.options.subfolderName,
  );

  @override
  void didUpdateWidget(OutputSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 参数被外部重置时（例如切换预设）同步输入框内容。
    // 条件是「和当前已输入内容不同，且确实来自外部变更」
    // ——自己敲出来的改动会重新进入这里，但不该触发回写。
    if (widget.options.namingTemplate != _template.text &&
        widget.options.namingTemplate != oldWidget.options.namingTemplate) {
      _template.text = widget.options.namingTemplate;
    }
    if (widget.options.subfolderName != _subfolder.text &&
        widget.options.subfolderName != oldWidget.options.subfolderName) {
      _subfolder.text = widget.options.subfolderName;
    }
  }

  @override
  void dispose() {
    _template.dispose();
    _subfolder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final options = widget.options;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('输出格式'),
        SegmentedControl<OutputFormat>(
          value: options.format,
          onChanged: (v) => widget.onChanged(options.copyWith(format: v)),
          segments: const [
            Segment(OutputFormat.original, '原格式'),
            Segment(OutputFormat.png, 'PNG'),
            Segment(OutputFormat.jpg, 'JPEG'),
            Segment(OutputFormat.webp, 'WebP'),
          ],
        ),
        const SizedBox(height: Gap.xl),

        const SectionLabel('保存位置'),
        SegmentedControl<OutputLocation>(
          value: options.location,
          onChanged: (v) => widget.onChanged(options.copyWith(location: v)),
          segments: const [
            Segment(OutputLocation.alongside, '原目录'),
            Segment(OutputLocation.subfolder, '子文件夹'),
            Segment(OutputLocation.custom, '指定目录'),
          ],
        ),
        const SizedBox(height: Gap.sm),

        if (options.location == OutputLocation.subfolder)
          IconField(
            controller: _subfolder,
            icon: Symbols.folder_open,
            hint: '子文件夹名称',
            onChanged: (value) =>
                widget.onChanged(options.copyWith(subfolderName: value)),
          ),

        if (options.location == OutputLocation.custom) ...[
          _DirectoryPicker(
            path: options.outputDir,
            onPicked: (dir) {
              widget.onChanged(options.copyWith(outputDir: dir));
              AppScope.of(context).settings.rememberOutputDir(dir);
            },
          ),
          const SizedBox(height: Gap.sm),
          _RecentDirs(
            onPick: (dir) => widget.onChanged(options.copyWith(outputDir: dir)),
          ),
        ],

        const SizedBox(height: Gap.xl),
        SectionLabel(
          '命名规则',
          trailing: Tooltip(
            message: OutputResolver.templateTokens.entries
                .map((e) => '${e.key}   ${e.value}')
                .join('\n'),
            child: Icon(Symbols.info, size: 14, color: t.textTertiary),
          ),
        ),
        TextField(
          controller: _template,
          style: text.bodyMedium,
          onChanged: (value) =>
              widget.onChanged(options.copyWith(namingTemplate: value)),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.md,
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        Row(
          children: [
            Icon(Symbols.description, size: 13, color: t.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '预览：${OutputResolverHints.preview(_template.text, options)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(color: t.textTertiary),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),

        SwitchRow(
          label: '覆盖同名文件',
          detail: options.overwrite ? '直接替换已有文件' : '自动追加序号，避免覆盖',
          value: options.overwrite,
          onChanged: (v) => widget.onChanged(options.copyWith(overwrite: v)),
        ),
      ],
    );
  }
}

class _DirectoryPicker extends StatelessWidget {
  const _DirectoryPicker({required this.path, required this.onPicked});

  final String? path;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final hasPath = path != null && path!.isNotEmpty;

    return InkWell(
      onTap: () async {
        final dir = await FileDialogs.pickDirectory(
          confirmButtonText: '选择输出目录',
        );
        if (dir != null) onPicked(dir);
      },
      borderRadius: Radii.allSm,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.md,
        ),
        decoration: BoxDecoration(
          color: t.surfaceSunken.withValues(alpha: 0.42),
          borderRadius: Radii.allSm,
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            Icon(Symbols.folder_open, size: 16, color: t.textTertiary),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                hasPath ? Fmt.ellipsisPath(path!, maxChars: 40) : '选择输出目录…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  color: hasPath ? t.textPrimary : t.textTertiary,
                ),
              ),
            ),
            Icon(Symbols.chevron_right, size: 16, color: t.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 最近使用过的输出目录，一键切换。
class _RecentDirs extends StatelessWidget {
  const _RecentDirs({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final recent = AppScope.of(context).settings.recentOutputDirs;
    if (recent.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        for (final dir in recent.take(4))
          Tooltip(
            message: dir,
            child: InkWell(
              onTap: () => onPick(dir),
              borderRadius: Radii.allSm,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: t.surfaceElevated.withValues(alpha: 0.45),
                  borderRadius: Radii.allSm,
                  border: Border.all(color: t.border),
                ),
                child: Text(
                  p.basename(dir),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: t.textSecondary),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 命名模板的示例预览。
///
/// 用固定的示例值渲染，让用户在输入模板时立刻看到最终文件名长什么样，
/// 而不是保存后才发现写错了占位符。
/// 渲染本身复用 [OutputResolver.renderTemplateString]，避免占位符替换
/// 逻辑在这里再抄一遍。
class OutputResolverHints {
  OutputResolverHints._();

  static String preview(String template, UpscaleOptions options) {
    final stem = OutputResolver.renderTemplateString(
      template,
      baseName: 'DSC_0421',
      scale: options.scale,
      modelId: options.modelId,
      outputWidth: 1600,
      outputHeight: 1200,
      now: DateTime(2026, 9, 18, 14, 30, 52),
    );
    final extension = options.format == OutputFormat.original
        ? 'png'
        : options.format.flag;
    return '$stem.$extension';
  }
}
