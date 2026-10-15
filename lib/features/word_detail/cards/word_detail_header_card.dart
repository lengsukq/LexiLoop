/// 词条详情页头部卡片。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/word_detail/dialogs/edit_word_dialog.dart';
import 'package:lexiloop/features/word_detail/dialogs/youdao_preview_dialog.dart';
import 'package:lexiloop/features/word_detail/word_detail_audio.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/status_badges.dart';

/// 词条头部：操作栏 + 文本、状态徽章、口音切换与学习开关。
///
/// 只接收数据，写操作通过 [wordDetailActionsProvider] 发起——
/// 旧版这一块收了 11 个 props 与 6 个回调，这里一个参数都不用传。
class WordDetailHeaderCard extends ConsumerWidget {
  /// 以词条详情构造。
  const new({required this.detail, super.key});

  /// 词条详情。
  final WordDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _HeaderActionBar(detail: detail),
        const SizedBox(height: 10),
        LiquidGlass(
          level: GlassLevel.elevated,
          borderRadius: BorderRadius.circular(LexiRadius.lg),
          showSpecular: true,
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _TermBlock(detail: detail),
              _TranslationHint(detail: detail),
              const SizedBox(height: 10),
              _PronunciationBar(detail: detail),
              const SizedBox(height: 10),
              _SourceMeta(detail: detail),
              const SizedBox(height: 6),
              _HeaderActions(detail: detail),
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部操作栏：补全内容、有道词典、编辑、重新生成、删除。
///
/// **为什么独立于卡片之外**：这些是「对这个词条做什么」，而卡片展示的是
/// 「这个词条是什么」。混在一张玻璃卡片里会让用户以为按钮只作用于卡片
/// 内部的某个分区。
class _HeaderActionBar extends ConsumerWidget {
  const new({required this.detail});

  final WordDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: () => unawaited(
            _initialize(context, ref, InitializationMode.fillMissingFields),
          ),
          icon: const Icon(Icons.auto_awesome_rounded, size: 16),
          label: const Text('补全缺失内容'),
        ),
        OutlinedButton.icon(
          onPressed: () =>
              unawaited(YoudaoPreviewDialog.show(context, wordId: detail.id)),
          icon: const Icon(Icons.menu_book_rounded, size: 16),
          label: const Text('有道词典'),
        ),
        OutlinedButton.icon(
          onPressed: () => unawaited(
            EditWordDialog.show(
              context,
              target: EditWordTarget(
                wordId: detail.id,
                term: detail.term,
                sourceLanguage: detail.sourceLanguage,
                targetLanguage: detail.targetLanguage,
                contentType: detail.contentType,
              ),
            ),
          ),
          icon: const Icon(Icons.edit_rounded, size: 16),
          label: const Text('编辑'),
        ),
        TextButton.icon(
          onPressed: () => unawaited(_confirmRegenerate(context, ref)),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('重新生成'),
        ),
        TextButton.icon(
          onPressed: () => unawaited(_confirmDelete(context, ref)),
          icon: Icon(
            Icons.delete_outline_rounded,
            size: 16,
            color: colors.danger,
          ),
          label: Text('删除', style: TextStyle(color: colors.danger)),
        ),
      ],
    );
  }

  /// 排一个初始化任务并提示。
  Future<void> _initialize(
    BuildContext context,
    WidgetRef ref,
    InitializationMode mode,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(wordDetailActionsProvider)
        .requestInitialization(detail.id, mode);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          mode == InitializationMode.forceOverwrite ? '已排入重新生成队列' : '已排入补全队列',
        ),
      ),
    );
  }

  /// 「重新生成」的二次确认。
  ///
  /// 必须确认：它会覆盖现有内容（虽然保留手动编辑的释义与例句），
  /// 误点一次就要等一次完整的重新抓取。
  Future<void> _confirmRegenerate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新生成'),
        content: const Text('重新生成会再次调用 AI，但会保留手动释义和例句。确定继续吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _initialize(context, ref, InitializationMode.forceOverwrite);
  }

  /// 二次确认后删除词条，并退出详情页。
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除词条'),
        content: Text(
          '确定删除「${detail.term}」吗？'
          '该词条的释义、例句、复习记录与错词状态都会一并删除，且无法恢复。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(wordDetailActionsProvider).delete(detail.id);
    if (context.mounted) await Navigator.of(context).maybePop();
  }
}

/// 朗读词条，失败或降级时提示原因。
///
/// 统一走 [speakWithWordSpeaker]（真人录音优先、系统朗读兜底）：
/// Android 缺语音包时系统 TTS 会静默无声，不提示的话用户只会觉得
/// 「按钮坏了」。
Future<void> _speakWord(
  BuildContext context,
  WidgetRef ref,
  WordDetail detail, {
  Accent? accent,
}) {
  final fromSelection = ref.read(selectedAccentProvider)[detail.id];
  return _speakWith(
    context,
    ref,
    detail,
    _resolveAccent(ref, fromSelection, accent),
  );
}

/// 决定这次朗读用哪个口音。
///
/// 优先级：显式指定的口音（点了某个口音的喇叭）> 该词条上次选中的口音 >
/// 设置里的默认口音。写成显式分支而不是 `??` 链：`??` 链在
/// `ref.read` 的泛型推断下会把整体类型推成可空，编译器无法替我们确认
/// 「一定拿得到一个口音」。
Accent _resolveAccent(WidgetRef ref, Accent? selected, Accent? override) {
  if (override != null) return override;
  if (selected != null) return selected;
  return ref.read(preferredAccentProvider);
}

/// 用指定口音朗读。
Future<void> _speakWith(
  BuildContext context,
  WidgetRef ref,
  WordDetail detail,
  Accent accent,
) {
  return speakWithWordSpeaker(
    context: context,
    ref: ref,
    term: detail.term,
    accent: accent,
    contentType: detail.contentType,
    pronunciations: detail.pronunciations,
  );
}

class _TermBlock extends StatelessWidget {
  const new({required this.detail});

  final WordDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          detail.term,
          style: LexiType.display.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            MasteryBadge(
              level: detail.masteryLevel,
              score: detail.masteryScore,
            ),
            InitializationBadge(status: detail.initializationStatus),
            DetailChip(
              text:
                  '${languageLabel(detail.sourceLanguage)} → '
                  '${languageLabel(detail.targetLanguage)}',
            ),
            DetailChip(text: contentTypeLabel(detail.contentType)),
            DetailChip(text: contentSourceLabel(detail.contentSource)),
            if (detail.isSuspended)
              DetailChip(text: '已暂停', color: colors.danger),
          ],
        ),
      ],
    );
  }
}

/// 「暂无中文释义 → AI 翻译释义」提示。
///
/// 只在**有英文释义而缺中文译文**时出现：什么内容都没有的词条该走
/// 「补全缺失内容」，那是另一条路径。
///
/// **与旧版的差异**：旧版把 busy 与结果文案放在页面上（`translationBusy` /
/// `translationMessage`）；这里改成入队后弹一条 SnackBar——翻译由后台
/// worker 执行，页面上留一个永远停在「翻译中」的状态没有意义。
class _TranslationHint extends ConsumerWidget {
  const new({required this.detail});

  final WordDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final short = detail.summary.shortDefinition?.trim() ?? '';
    final translation = detail.summary.translation?.trim() ?? '';
    if (short.isEmpty || translation.isNotEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: <Widget>[
          Text(
            '暂无中文释义',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => unawaited(_request(context, ref)),
            icon: const Icon(Icons.translate_rounded, size: 15),
            label: const Text('AI 翻译释义'),
          ),
        ],
      ),
    );
  }

  Future<void> _request(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(wordDetailActionsProvider).requestTranslation(detail.id);
    messenger.showSnackBar(const SnackBar(content: Text('已加入翻译队列')));
  }
}

/// 口音切换栏：把 US / UK 两个音标并排展示，各自可点选、各自可朗读。
///
/// 旧版只显示一个口音，另一个音标要切全局设置才看得到——用户根本不知道
/// 这个词还有英音，于是记不住的那个读音就永远不会被复习到。
class _PronunciationBar extends ConsumerWidget {
  const new({required this.detail});

  final WordDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferred = ref.watch(preferredAccentProvider);
    final selection = ref.watch(selectedAccentProvider);
    final accent = selection[detail.id] ?? preferred;
    final available = <Accent>[
      for (final item in Accent.values)
        if (detail.pronunciations.any((one) => one.accent == item)) item,
    ];
    if (available.isEmpty) return _PlainPlayButton(detail: detail);
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: <Widget>[
        for (final item in available)
          _AccentToggle(detail: detail, accent: item, selected: item == accent),
      ],
    );
  }
}

/// 一个口音：点胶囊选它，点喇叭只朗读、不改选择。
///
/// 选中与朗读分成两个控件是因为它们回答的是不同问题：「我该学哪个读音」
/// 与「这个读音怎么念」。合成一个按钮的话，想只听不改就没法只听不改。
class _AccentToggle extends ConsumerWidget {
  const new({
    required this.detail,
    required this.accent,
    required this.selected,
  });

  final WordDetail detail;
  final Accent accent;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final phonetic =
        preferredPronunciation(detail.pronunciations, accent)?.phonetic ?? '';
    final label = accentLabel(accent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        GestureDetector(
          onTap: () => ref
              .read(selectedAccentProvider.notifier)
              .select(detail.id, accent),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? colors.accent.withValues(alpha: 0.16)
                  : Colors.transparent,
              border: Border.all(
                color: selected ? colors.accent : colors.separator,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: LexiType.body.copyWith(
                    color: selected ? colors.accent : colors.secondaryLabel,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (phonetic.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    '/$phonetic/',
                    style: LexiType.footnote.copyWith(
                      color: colors.secondaryLabel,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: '朗读$label式发音',
          visualDensity: VisualDensity.compact,
          onPressed: () =>
              unawaited(_speakWord(context, ref, detail, accent: accent)),
          icon: Icon(Icons.volume_up_rounded, size: 18, color: colors.accent),
        ),
      ],
    );
  }
}

/// 没有任何音标时的兜底朗读按钮。
class _PlainPlayButton extends ConsumerWidget {
  const new({required this.detail});

  final WordDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => unawaited(_speakWord(context, ref, detail)),
        icon: const Icon(Icons.volume_up_rounded, size: 18),
        label: const Text('播放发音'),
      ),
    );
  }
}

/// 「创建 / 更新 / 源内容时间」一行。
///
/// 三个时间回答三个不同的问题：词条是何时进库的、内容最后一次是何时被我
/// 改的、词典条目本身是何时写的。只显示第一个的话，用户会把自己手动改过的
/// 词条误当成「当初就这样导入的」。
class _SourceMeta extends StatelessWidget {
  const new({required this.detail});

  final WordDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _metaLine(colors, '创建于 ${formatTimestamp(detail.createdAt)}'),
        if (detail.updatedAt != null && detail.updatedAt != detail.createdAt)
          _metaLine(colors, '更新于 ${formatTimestamp(detail.updatedAt!)}'),
        if (detail.sourceCreatedAt != null)
          _metaLine(
            colors,
            '源内容时间 ${formatTimestamp(detail.sourceCreatedAt!)}',
          ),
      ],
    );
  }

  Widget _metaLine(LexiColors colors, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      text,
      style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
    ),
  );
}

/// 卡片底部：朗读、学习状态与暂停开关。
class _HeaderActions extends ConsumerWidget {
  const new({required this.detail});

  final WordDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: '朗读',
          onPressed: () => unawaited(_speakWord(context, ref, detail)),
          icon: const Icon(Icons.volume_up_rounded),
        ),
        const Spacer(),
        Text(
          detail.isSuspended ? '已暂停' : '学习中',
          style: LexiType.body.copyWith(color: colors.secondaryLabel),
        ),
        Switch(
          value: detail.isSuspended,
          onChanged: (value) => ref
              .read(wordDetailActionsProvider)
              .setSuspended(detail.id, suspended: value),
        ),
      ],
    );
  }
}
