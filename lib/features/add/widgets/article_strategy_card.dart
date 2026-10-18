/// 导入策略卡：模式选择 + 确认导入。
///
/// 对应旧版 `article-tab.tsx` 的 `ImportStrategyCard`。
///
/// **与旧版的差异（有意）**：旧版这张卡还有一枚「重置本次已有词条的学习进度」
/// 复选框，实现要删复习日志 / 复习卡 / 错词状态并撤下未作答题——那段逻辑只在
/// `CsvImportService` 内部（私有），而 `WordEditService` 没有等价入口。
/// 摆一个做不到的复选框比没有它更糟，因此本版不显示它，并在服务层注释里
/// 记录了这条能力缺口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/add/article_providers.dart';
import 'package:lexiloop/features/add/widgets/article_common.dart';
import 'package:lexiloop/ui/feedback/confirm_dialog.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/reset_progress_option.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 导入策略卡。
class ArticleStrategyCard extends ConsumerWidget {
  /// 创建策略卡。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(articleWizardProvider);
    final notifier = ref.read(articleWizardProvider.notifier);
    final canCommit =
        state.selection.selected.isNotEmpty &&
        state.analysis.finalToken != null;
    return ArticleSectionCard(
      title: '导入策略',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final mode in ImportMode.values)
            _ModeOption(
              mode: mode,
              selected: state.selection.mode == mode,
              onTap: () => notifier.setMode(mode),
            ),
          const SizedBox(height: articleTightGap),
          ResetProgressOption(
            value: state.selection.resetLearningProgress,
            onChanged: (next) => notifier.setResetLearningProgress(value: next),
          ),
          if (state.error != null) ...<Widget>[
            const SizedBox(height: articleTightGap),
            ArticleErrorBanner(message: state.error!),
          ],
          const SizedBox(height: articleCardGap),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('articleCommit'),
              onPressed: canCommit
                  ? () => _commitWithConfirm(context, notifier, state)
                  : null,
              icon: const Icon(LucideIcons.arrowRight, size: 16),
              label: Text('确认导入 ${state.selection.selected.length} 个'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const new({required this.mode, required this.selected, required this.onTap});

  final ImportMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: articleTightGap),
      child: Material(
        color: selected
            ? colors.accent.withValues(alpha: LexiTint.tint)
            : colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: InkWell(
          key: Key('articleMode${mode.wire}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(LexiRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s12,
              vertical: LexiSpace.s10,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  selected ? LucideIcons.circleDot : LucideIcons.circle,
                  size: 17,
                  color: selected ? colors.accent : colors.tertiaryLabel,
                ),
                const SizedBox(width: LexiSpace.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        articleModeLabel(mode),
                        style: LexiType.body.copyWith(
                          color: selected ? colors.accent : colors.label,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        articleModeDescription(mode),
                        style: LexiType.footnote.copyWith(
                          color: colors.secondaryLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 导入模式的中文名。
String articleModeLabel(ImportMode mode) => switch (mode) {
  ImportMode.fillMissing => '智能补充',
  ImportMode.skipExisting => '仅新增',
  ImportMode.forceDictionaryRefresh => '强制刷新',
};

/// 导入模式的说明。
String articleModeDescription(ImportMode mode) => switch (mode) {
  ImportMode.fillMissing => '新增词条，并给已有词条补充缺失的释义、发音和例句。',
  ImportMode.skipExisting => '已有词条完全跳过，不创建内容补全任务。',
  ImportMode.forceDictionaryRefresh => '重新查询已有词条的词典内容，但保留学习进度。',
};

/// 提交前把「重置学习进度」的确认补上。
///
/// **同一件事在两条路径上谨慎度不同**：CSV 导入在提交时会弹一个
/// 不可撤销确认（`import_page.dart` 的 `_ResetProgressDialog`），
/// 而文章导入这边勾上就直接写——勾选框本身只是一次点击，很容易
/// 在滚动候选词的时候被顺手带上。这里对齐成同一条规则：
/// 只要勾了「重置学习进度」，提交前必须再确认一次。
Future<void> _commitWithConfirm(
  BuildContext context,
  ArticleWizardNotifier notifier,
  ArticleWizardState state,
) async {
  if (state.selection.resetLearningProgress) {
    final confirmed = await confirmAction(
      context,
      title: '重置已有词条的学习进度？',
      // 文案直接复用勾选项的说明，两处说的必须是同一件事。
      body: '$resetProgressDescription\n\n这一步不可撤销。',
      confirmLabel: '重置并导入',
      destructive: true,
    );
    if (!confirmed) return;
  }
  await notifier.commit();
}
