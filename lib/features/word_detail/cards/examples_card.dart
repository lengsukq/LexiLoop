/// 例句卡片。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/word_detail/word_detail_audio.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 例句卡片：句子 + 翻译 + 逐条操作（朗读 / 翻译 / 删除）。
///
/// 调用方保证 [examples] 非空，否则整卡不显示。
class ExamplesCard extends ConsumerWidget {
  /// 以词条 ID 与例句列表构造。
  const new({required this.wordId, required this.examples, super.key});

  /// 词条 ID；三个操作都要靠它落库或入队。
  final int wordId;

  /// 例句列表。
  final List<ExampleView> examples;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      variant: SurfaceVariant.plain,
      tone: LexiTone.sky,
      title: '例句',
      icon: LucideIcons.quote,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var index = 0; index < examples.length; index += 1)
            _ExampleRow(wordId: wordId, index: index, item: examples[index]),
        ],
      ),
    );
  }
}

/// 一条例句与它的三个操作。
///
/// **下标即界面顺序**：`WordEditService.deleteExample` 会按
/// `detailExamplePositions` 把它换算回 `examples_json` 的真实下标，
/// 因此这里不需要、也不应该自己去数原始 JSON 的位置。
class _ExampleRow extends ConsumerWidget {
  const new({required this.wordId, required this.index, required this.item});

  final int wordId;
  final int index;
  final ExampleView item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LexiSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.sentence,
            style: LexiType.callout.copyWith(color: colors.label),
          ),
          if (item.translation != null)
            Padding(
              padding: const EdgeInsets.only(top: LexiSpace.s2),
              child: Text(
                item.translation!,
                style: LexiType.body.copyWith(color: colors.secondaryLabel),
              ),
            ),
          if (item.difficulty != null || item.senseId != null)
            Padding(
              padding: const EdgeInsets.only(top: LexiSpace.s2),
              child: Text(
                <String>[
                  if (item.difficulty != null) '难度 ${item.difficulty}',
                  if (item.senseId != null) '义项 ${item.senseId}',
                ].join(' · '),
                style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ExampleAction(
                tooltip: '朗读这句',
                icon: LucideIcons.volume2,
                onPressed: () => unawaited(_speak(context, ref)),
              ),
              _ExampleAction(
                tooltip: 'AI 翻译这句',
                icon: LucideIcons.languages,
                onPressed: () => unawaited(_translate(context, ref)),
              ),
              _ExampleAction(
                tooltip: '删除这句',
                icon: LucideIcons.trash2,
                color: colors.danger,
                onPressed: () => _confirmDelete(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 朗读例句原文。
  ///
  /// 走与词条相同的 [speakWithWordSpeaker]：例句没有音标与音频地址，
  /// `WordSpeaker` 因此必然回落到系统朗读，但它统一了语速档位（句子档）
  /// 与失败提示，不必在这里再抄一遍。
  ///
  /// **与旧版的差异**：旧版按词条的 `sourceLanguage` 选语言（`en` →
  /// `en-US`），而 `SpeechRequest` 只按口音选语言，因此例句固定读作英语
  /// 口音。例句本来就都是英文，实际听感与旧版一致。
  Future<void> _speak(BuildContext context, WidgetRef ref) =>
      speakWithWordSpeaker(
        context: context,
        ref: ref,
        term: item.sentence,
        accent: ref.read(preferredAccentProvider),
        contentType: LexicalContentType.sentence,
      );

  /// 排一个 AI 翻译任务。
  ///
  /// 译文由 worker 回填，因此这里**不做乐观更新**：立刻在界面上补一行
  /// 「翻译中…」占位，任务失败时用户会看到一条永远填不满的假译文。
  Future<void> _translate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(wordDetailActionsProvider).translateExample(wordId, index);
      messenger.showSnackBar(const SnackBar(content: Text('已加入翻译队列')));
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// 二次确认后删除这条例句。
  ///
  /// 必须确认：例句可能是整份 AI 内容里唯一的可用素材，误删之后只能靠
  /// 重新初始化整个词条才能拿回来。
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除例句'),
        content: const Text('确定删除这条例句吗？该操作无法撤销。'),
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
    try {
      await ref.read(wordDetailActionsProvider).deleteExample(wordId, index);
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// 例句行上的一个图标按钮。
class _ExampleAction extends StatelessWidget {
  const new({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon, size: 17, color: color ?? colors.secondaryLabel),
    );
  }
}
