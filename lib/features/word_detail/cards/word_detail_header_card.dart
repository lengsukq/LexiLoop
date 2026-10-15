/// 词条详情页头部卡片。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/status_badges.dart';

/// 词条头部：文本、状态徽章、口音切换与操作按钮。
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
    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      showSpecular: true,
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _TermBlock(detail: detail),
          const SizedBox(height: 10),
          _PronunciationBar(detail: detail),
          const SizedBox(height: 10),
          _SourceMeta(detail: detail),
          const SizedBox(height: 6),
          _HeaderActions(detail: detail),
        ],
      ),
    );
  }
}

/// 朗读词条，失败时提示原因。
///
/// Android 缺语音包时系统 TTS 会静默无声，不提示的话用户只会觉得
/// 「按钮坏了」。抽成顶层函数是因为发音栏上每个口音都要一个播放按钮，
/// 与头部那一个共用同一段失败处理。
///
/// **暂不按口音切换音色**：`TtsService` 目前只按 `sourceLanguage` 选音色，
/// 播放按钮先按口音拆开是为了让界面结构一步到位；口音真正生效要等新的
/// 音频层落地，届时只需改这一处。
Future<void> _speakWord(
  BuildContext context,
  WidgetRef ref,
  WordDetail detail,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final playback =
      ref.read(appSettingsProvider).value?.playback ??
      PlaybackSettings.defaults;
  try {
    await ref
        .read(ttsServiceProvider)
        .speakTerm(
          term: detail.term,
          sourceLanguage: detail.sourceLanguage,
          contentType: detail.contentType,
          playback: playback,
        );
  } on AppError catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  }
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
          style: TextStyle(
            color: colors.label,
            fontSize: 30,
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
                  style: TextStyle(
                    color: selected ? colors.accent : colors.secondaryLabel,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (phonetic.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    '/$phonetic/',
                    style: TextStyle(
                      color: colors.secondaryLabel,
                      fontSize: 12.5,
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
          onPressed: () => unawaited(_speakWord(context, ref, detail)),
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
      style: TextStyle(color: colors.tertiaryLabel, fontSize: 11.5),
    ),
  );
}

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
          style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
        ),
        Switch(
          value: detail.isSuspended,
          onChanged: (value) => ref
              .read(wordDetailActionsProvider)
              .setSuspended(detail.id, suspended: value),
        ),
        IconButton(
          tooltip: '删除词条',
          onPressed: () => _confirmDelete(context, ref),
          icon: Icon(Icons.delete_outline_rounded, color: colors.danger),
        ),
      ],
    );
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
