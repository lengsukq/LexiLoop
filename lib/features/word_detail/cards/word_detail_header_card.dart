/// 词条详情页头部卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/status_badges.dart';

/// 词条头部：文本、音标、状态徽章与操作按钮。
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
    final accent = ref.watch(preferredAccentProvider);
    final pronunciation = preferredPronunciation(detail.pronunciations, accent);

    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      showSpecular: true,
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _TermBlock(detail: detail, phonetic: pronunciation?.phonetic),
          const SizedBox(height: 12),
          _HeaderActions(detail: detail),
        ],
      ),
    );
  }
}

class _TermBlock extends StatelessWidget {
  const new({required this.detail, this.phonetic});

  final WordDetail detail;
  final String? phonetic;

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
        if (phonetic != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            '/$phonetic/',
            style: TextStyle(
              color: colors.secondaryLabel,
              fontSize: 15,
              fontFamily: 'monospace',
            ),
          ),
        ],
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

class _HeaderActions extends ConsumerWidget {
  const new({required this.detail});

  final WordDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        // 朗读尚未接入：按钮禁用并说明原因，而不是留一个点了没反应的图标。
        const Tooltip(
          message: '朗读功能待接入',
          child: IconButton(
            onPressed: null,
            icon: Icon(Icons.volume_up_rounded),
          ),
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
