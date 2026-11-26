/// 文章导入的第一步：粘贴正文与选择分析参数。
///
/// 对应旧版 `article-tab.tsx` 的 `step === "input"` 分支：考试目标多选、
/// 正文输入（带字符计数）、分段方案预览与「单次 / 分批」两个分析入口。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/add/article_providers.dart';
import 'package:lexiloop/features/add/widgets/article_common.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 考试目标的中文名（全 9 档）。
const Map<VocabularyLevel, String> articleExamTargetLabels =
    <VocabularyLevel, String>{
      VocabularyLevel.gaokao: '高考',
      VocabularyLevel.cet4: 'CET-4',
      VocabularyLevel.cet6: 'CET-6',
      VocabularyLevel.ky: '考研',
      VocabularyLevel.tem4: '专四',
      VocabularyLevel.tem8: '专八',
      VocabularyLevel.ielts: '雅思',
      VocabularyLevel.toefl: '托福',
      VocabularyLevel.gre: 'GRE',
    };

/// 第一步的说明文案。
final String _inputHint = <String>[
  'LLM 负责按所选难度智能分词并还原词形，导入后自动通过有道词典查询音标、释义与例句；',
  '未配置 AI 时也可使用本地分词导入。',
].join();

/// 第一步界面。
class ArticleInputStep extends ConsumerWidget {
  /// 创建第一步界面。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(articleWizardProvider);
    final plan = state.draft.plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ArticleSectionCard(
          title: '导入英文文章',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _inputHint,
                style: LexiType.footnote.copyWith(
                  color: context.lexiColors.secondaryLabel,
                ),
              ),
              const SizedBox(height: articleTightGap),
              const _AiReadinessBar(),
              const SizedBox(height: articleCardGap),
              const _ExamTargetPicker(),
              const SizedBox(height: articleCardGap),
              const _TokenizeOptions(),
              const SizedBox(height: articleCardGap),
              const _SourceImportBar(),
              const SizedBox(height: articleTightGap),
              const _ArticleTextField(),
              if (plan != null && plan.segments.length > 1) ...<Widget>[
                const SizedBox(height: articleCardGap),
                _SegmentPlanCard(plan: plan),
              ],
              if (plan != null && plan.segments.length <= 1) ...<Widget>[
                const SizedBox(height: articleTightGap),
                Text(
                  '当前为单段，将一次性请求；如需分段请用空行分隔段落。',
                  style: LexiType.footnote.copyWith(
                    color: context.lexiColors.tertiaryLabel,
                  ),
                ),
              ],
              if (state.error != null) ...<Widget>[
                const SizedBox(height: articleCardGap),
                ArticleErrorBanner(message: state.error!),
              ],
              const SizedBox(height: articleCardGap),
              _AnalyzeButtons(plan: plan),
            ],
          ),
        ),
      ],
    );
  }
}

class _AiReadinessBar extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) return const SizedBox.shrink();
    final llm = llmConfigFromSettings(settings.raw);
    final ready = llm.canArticleTokenize;
    return Wrap(
      spacing: LexiSpace.s8,
      runSpacing: LexiSpace.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        ArticleBadge(
          label: ready
              ? 'AI 分词已就绪 · ${llm.ai.model} · 有道查词'
              : '未启用 AI 分词 · 将使用本地提词',
          tone: ready ? LexiBadgeTone.purple : LexiBadgeTone.warning,
        ),
        TextButton(
          key: const Key('articleOpenAiSettings'),
          onPressed: () {
            final router = GoRouter.maybeOf(context);
            router?.go('$settingsPath?tab=ai');
          },
          child: Text(ready ? '调整 AI 设置' : '去配置 AI'),
        ),
      ],
    );
  }
}

class _TokenizeOptions extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final state = ref.watch(articleWizardProvider);
    final notifier = ref.read(articleWizardProvider.notifier);
    return Wrap(
      spacing: LexiSpace.s16,
      runSpacing: LexiSpace.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Wrap(
          spacing: LexiSpace.s6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              '难度口径：',
              style: LexiType.caption.copyWith(color: colors.secondaryLabel),
            ),
            ChoiceChip(
              key: const Key('articleModeAtOrAbove'),
              label: const Text('该级别及以上'),
              selected:
                  state.draft.difficultyMode == ArticleDifficultyMode.atOrAbove,
              onSelected: (_) =>
                  notifier.setDifficultyMode(ArticleDifficultyMode.atOrAbove),
            ),
            ChoiceChip(
              key: const Key('articleModeExactBand'),
              label: const Text('精准匹配该级别'),
              selected:
                  state.draft.difficultyMode == ArticleDifficultyMode.exactBand,
              onSelected: (_) =>
                  notifier.setDifficultyMode(ArticleDifficultyMode.exactBand),
            ),
          ],
        ),
        Wrap(
          spacing: LexiSpace.s6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              '提取范围：',
              style: LexiType.caption.copyWith(color: colors.secondaryLabel),
            ),
            ChoiceChip(
              key: const Key('articleScopeWordsOnly'),
              label: const Text('仅分词（快速）'),
              selected:
                  state.draft.extractScope == ArticleExtractScope.wordsOnly,
              onSelected: (_) =>
                  notifier.setExtractScope(ArticleExtractScope.wordsOnly),
            ),
            ChoiceChip(
              key: const Key('articleScopeFull'),
              label: const Text('含短语与难句'),
              selected:
                  state.draft.extractScope ==
                  ArticleExtractScope.withPhrasesAndSentences,
              onSelected: (_) => notifier.setExtractScope(
                ArticleExtractScope.withPhrasesAndSentences,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SourceImportBar extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final state = ref.watch(articleWizardProvider);
    final notifier = ref.read(articleWizardProvider.notifier);
    final busy = state.draft.loadingSource;
    return Wrap(
      spacing: LexiSpace.s8,
      runSpacing: LexiSpace.s6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        OutlinedButton.icon(
          key: const Key('articlePasteClipboard'),
          onPressed: busy ? null : () => unawaited(_paste(notifier)),
          icon: const Icon(LucideIcons.clipboardPaste, size: 15),
          label: const Text('粘贴剪贴板'),
        ),
        OutlinedButton.icon(
          key: const Key('articlePickFile'),
          onPressed: busy ? null : notifier.importLocalFile,
          icon: const Icon(LucideIcons.fileUp, size: 15),
          label: const Text('导入文件'),
        ),
        OutlinedButton.icon(
          key: const Key('articleFetchUrl'),
          onPressed: busy
              ? null
              : () => unawaited(_promptUrl(context, notifier)),
          icon: const Icon(LucideIcons.globe, size: 15),
          label: const Text('抓取网页'),
        ),
        if (busy)
          const SizedBox(
            width: LexiSpace.s16,
            height: LexiSpace.s16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (state.draft.sourceLabel != null)
          Text(
            '来源：${state.draft.sourceLabel}',
            style: LexiType.caption.copyWith(color: colors.secondaryLabel),
          ),
      ],
    );
  }

  Future<void> _paste(ArticleWizardNotifier notifier) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    await notifier.ingestExternalText(text);
  }

  Future<void> _promptUrl(
    BuildContext context,
    ArticleWizardNotifier notifier,
  ) async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => const _UrlPromptDialog(),
    );
    if (url != null && url.isNotEmpty) {
      await notifier.fetchWebUrl(url);
    }
  }
}

class _UrlPromptDialog extends StatefulWidget {
  const new();

  @override
  State<_UrlPromptDialog> createState() => _UrlPromptDialogState();
}

class _UrlPromptDialogState extends State<_UrlPromptDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('抓取英文网页正文'),
    content: TextField(
      key: const Key('articleUrlInput'),
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(
        hintText: 'https://example.com/article',
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('articleUrlConfirm'),
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('抓取正文'),
      ),
    ],
  );
}

class _ExamTargetPicker extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final state = ref.watch(articleWizardProvider);
    final notifier = ref.read(articleWizardProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '考试目标 · 可多选，不选为自适应（支持跨档如四级 + 托福）',
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
        const SizedBox(height: articleTightGap),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final entry in articleExamTargetLabels.entries)
              _ExamTargetChip(
                label: entry.value,
                level: entry.key,
                active: state.draft.examTargets.contains(entry.key),
                onTap: () => notifier.toggleExamTarget(entry.key),
              ),
            if (state.draft.examTargets.isNotEmpty)
              TextButton(
                key: const Key('articleClearExamTargets'),
                onPressed: notifier.clearExamTargets,
                child: const Text('清空'),
              ),
          ],
        ),
        Text(
          state.draft.examTargets.isEmpty
              ? (state.draft.examTargetsLoaded ? '当前：自适应（按已掌握词库）' : '正在读取设置…')
              : '已选 ${state.draft.examTargets.length} 档，多档时就高不就低',
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
        ),
      ],
    );
  }
}

class _ExamTargetChip extends StatelessWidget {
  const new({
    required this.label,
    required this.level,
    required this.active,
    required this.onTap,
  });

  final String label;
  final VocabularyLevel level;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Material(
      color: active ? colors.accent : colors.fill,
      borderRadius: BorderRadius.circular(LexiRadius.xxl),
      child: InkWell(
        key: Key('articleExamTarget${level.wire}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(LexiRadius.xxl),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LexiSpace.s12,
            vertical: LexiSpace.s6,
          ),
          child: Text(
            label,
            style: LexiType.footnote.copyWith(
              color: active ? colors.onAccent : colors.secondaryLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 正文输入框。
///
/// **为什么是有状态组件**：输入框要能被「填入示例 / 清空」从外部改写，
/// 而 `onChanged` 又要回写状态；只靠 `TextField` 自己的内部状态会让按钮
/// 改不动它。控制器与状态之间做单向同步（不同才覆盖），用户输入时两者
/// 已经相等，不会打断光标。
class _ArticleTextField extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_ArticleTextField> createState() => _ArticleTextFieldState();
}

class _ArticleTextFieldState extends ConsumerState<_ArticleTextField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final state = ref.watch(articleWizardProvider);
    final notifier = ref.read(articleWizardProvider.notifier);
    final tooShort = state.charCount < minArticleChars;
    final tooLong = state.charCount > maxArticleChars;
    if (_controller.text != state.draft.text) {
      _controller.value = TextEditingValue(
        text: state.draft.text,
        selection: TextSelection.collapsed(offset: state.draft.text.length),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          key: const Key('articleText'),
          controller: _controller,
          onChanged: notifier.setArticleText,
          maxLines: 10,
          minLines: 8,
          maxLength: maxArticleChars,
          style: LexiType.callout.copyWith(color: colors.label),
          decoration: InputDecoration(
            hintText: articleSampleArticle,
            hintStyle: LexiType.body.copyWith(color: colors.tertiaryLabel),
            counterText: '',
            filled: true,
            fillColor: colors.fill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LexiRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${state.charCount} / $maxArticleChars 字符 · 至少 $minArticleChars 字符',
                style: LexiType.caption.copyWith(
                  color: tooLong
                      ? colors.danger
                      : (tooShort ? colors.warning : colors.tertiaryLabel),
                ),
              ),
            ),
            TextButton(
              key: const Key('articleFillSample'),
              onPressed: () => notifier.setArticleText(articleSampleArticle),
              child: const Text('填入示例'),
            ),
            TextButton(
              key: const Key('articleClearText'),
              onPressed: state.charCount == 0
                  ? null
                  : () => notifier.setArticleText(''),
              child: const Text('清空'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SegmentPlanCard extends ConsumerWidget {
  const new({required this.plan});

  final ArticleSegmentPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final state = ref.watch(articleWizardProvider);
    final notifier = ref.read(articleWizardProvider.notifier);
    final perBatchHint = plan.batches.length > 1
        ? '（每批 ${state.draft.segmentsPerBatch} 段）'
        : '';
    return Container(
      padding: const EdgeInsets.all(articleCardPadding),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '智能分段预览',
            style: LexiType.body.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '按换行智能识别为 ${plan.segments.length} 段 · 共 ${plan.totalChars} 字符 · '
            '将分 ${plan.batches.length} 次请求$perBatchHint',
            style: LexiType.caption.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: articleTightGap),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final batch in plan.batches)
                ArticleBadge(
                  label: '第 ${batch.batchIndex + 1} 批 · ${batch.charCount} 字',
                  tone: LexiBadgeTone.accent,
                ),
            ],
          ),
          const SizedBox(height: articleTightGap),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '每批段数：${state.draft.segmentsPerBatch} 段 / 批（1 段最稳、'
                  '$maxArticleSegmentsPerBatch 段最快）',
                  style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
                ),
              ),
              Slider(
                key: const Key('articleBatchSize'),
                value: state.draft.segmentsPerBatch.toDouble(),
                min: 1,
                max: maxArticleSegmentsPerBatch.toDouble(),
                divisions: maxArticleSegmentsPerBatch - 1,
                label: '${state.draft.segmentsPerBatch}',
                onChanged: (value) =>
                    notifier.setSegmentsPerBatch(value.round()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalyzeButtons extends ConsumerWidget {
  const new({required this.plan});

  final ArticleSegmentPlan? plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(articleWizardProvider);
    final notifier = ref.read(articleWizardProvider.notifier);
    final canAnalyze = state.canAnalyze;
    final batches = plan?.batches.length ?? 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        if (plan != null && plan!.segments.length > 1) ...<Widget>[
          OutlinedButton(
            key: const Key('articleAnalyzeSingle'),
            onPressed: canAnalyze ? notifier.analyzeSingle : null,
            child: Text('单次请求（${state.charCount} 字）'),
          ),
          const SizedBox(width: LexiSpace.s8),
          FilledButton.icon(
            key: const Key('articleAnalyzeSegmented'),
            onPressed: canAnalyze ? notifier.analyzeSegmented : null,
            icon: const Icon(LucideIcons.sparkles, size: 16),
            label: Text('分 $batches 批分析'),
          ),
        ] else
          FilledButton.icon(
            key: const Key('articleAnalyze'),
            onPressed: canAnalyze ? notifier.analyzeSingle : null,
            icon: const Icon(LucideIcons.sparkles, size: 16),
            label: const Text('智能分析'),
          ),
      ],
    );
  }
}
