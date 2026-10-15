/// 例句卡片。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 例句卡片：句子 + 翻译 + 逐条操作（朗读 / 翻译 / 删除）。
///
/// 调用方保证 [examples] 非空，否则整卡不显示。
class ExamplesCard extends ConsumerWidget {
  /// 以词条 ID、源语言与例句列表构造。
  const new({
    required this.wordId,
    required this.sourceLanguage,
    required this.examples,
    super.key,
  });

  /// 词条 ID；三个操作都要靠它落库或入队。
  final int wordId;

  /// 词条的源语言代码；朗读时用它选音色。
  final String sourceLanguage;

  /// 例句列表。
  final List<ExampleView> examples;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DetailSectionCard(
      title: '例句',
      icon: Icons.format_quote_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var index = 0; index < examples.length; index += 1)
            _ExampleRow(
              wordId: wordId,
              index: index,
              item: examples[index],
              sourceLanguage: sourceLanguage,
            ),
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
  const new({
    required this.wordId,
    required this.index,
    required this.item,
    required this.sourceLanguage,
  });

  final int wordId;
  final int index;
  final ExampleView item;
  final String sourceLanguage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.sentence,
            style: TextStyle(color: colors.label, fontSize: 14, height: 1.45),
          ),
          if (item.translation != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                item.translation!,
                style: TextStyle(
                  color: colors.secondaryLabel,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          if (item.difficulty != null || item.senseId != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                <String>[
                  if (item.difficulty != null) '难度 ${item.difficulty}',
                  if (item.senseId != null) '义项 ${item.senseId}',
                ].join(' · '),
                style: TextStyle(color: colors.tertiaryLabel, fontSize: 11.5),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ExampleAction(
                tooltip: '朗读这句',
                icon: Icons.volume_up_rounded,
                onPressed: () => unawaited(_speak(context, ref)),
              ),
              _ExampleAction(
                tooltip: 'AI 翻译这句',
                icon: Icons.translate_rounded,
                onPressed: () => unawaited(_translate(context, ref)),
              ),
              _ExampleAction(
                tooltip: '删除这句',
                icon: Icons.delete_outline_rounded,
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
  Future<void> _speak(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final playback =
        ref.read(appSettingsProvider).value?.playback ??
        PlaybackSettings.defaults;
    try {
      await ref
          .read(ttsServiceProvider)
          .speak(
            item.sentence,
            languageCode: sourceLanguage,
            rate: playback.speedFor(null),
          );
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

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
