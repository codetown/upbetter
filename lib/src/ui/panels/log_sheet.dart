import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/app_paths.dart';
import '../../core/util/log.dart';
import '../theme/tokens.dart';
import '../util/system.dart';
import '../widgets/primitives.dart';

/// 运行日志抽屉。排查推理失败时，这里是第一手信息。
class LogSheet extends StatelessWidget {
  const LogSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LogSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.6,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.md, Gap.md),
            child: Row(
              children: [
                Icon(Symbols.description, size: 17, color: t.textSecondary),
                const SizedBox(width: Gap.sm),
                Text('运行日志', style: text.titleMedium),
                const Spacer(),
                IconBtn(
                  icon: Symbols.folder_open,
                  tooltip: '打开日志文件所在目录',
                  onPressed: () => SystemShell.revealFile(AppPaths.logFile.path),
                ),
                IconBtn(
                  icon: Symbols.close,
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.border),
          Expanded(
            child: StreamBuilder<LogEntry>(
              stream: Log.stream,
              builder: (context, _) {
                final entries = Log.recent.reversed.toList();
                if (entries.isEmpty) {
                  return Center(
                    child: Text('暂无日志', style: text.bodySmall),
                  );
                }
                return ListView.builder(
                  reverse: false,
                  padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                  itemCount: entries.length,
                  itemExtent: 22,
                  itemBuilder: (context, index) => _LogRow(entry: entries[index], tokens: t),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.tokens});

  final LogEntry entry;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      LogLevel.error => tokens.danger,
      LogLevel.warn => tokens.warning,
      LogLevel.info => tokens.textSecondary,
      LogLevel.debug => tokens.textTertiary,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            entry.time.toIso8601String().substring(11, 19),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          const SizedBox(width: Gap.md),
          SizedBox(
            width: 62,
            child: Text(
              entry.tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tokens.textTertiary),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              entry.message.replaceAll('\n', '  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
