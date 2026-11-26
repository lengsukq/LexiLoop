/// 关联词弹窗：预览关系信息与词库状态，并把它加入词库。
///
/// 对应旧版
/// `src/app/(main)/words/[id]/components/related-word-dialog.tsx`。
///
/// **为什么要有这个弹窗而不是「点一下就加」**：同一个词可能在词库里已经
/// 存在（甚至已经学过了）。直接加入会建出一个重复词条，或者让用户以为
/// 自己新加了一个词。弹窗先回答「它现在在不在库里、内容全不全」，
/// 再决定按钮是「加入初始化」还是「加入词库并初始化」。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/models/word_content_models.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/status_badges.dart';

/// 弹窗内容宽度。
const double relatedWordDialogWidth = 420;

/// 关联词弹窗。
class RelatedWordDialog extends ConsumerStatefulWidget {
  /// 以父词条 ID、关联词文本与关系类型构造。
  const new({
    required this.parentWordId,
    required this.term,
    required this.relation,
    this.onAdded,
    super.key,
  });

  /// 父词条 ID。
  final int parentWordId;

  /// 关联词文本。
  final String term;

  /// 该关联词与父词条的关系。
  final RelationType relation;

  /// 成功加入词库后的回调（用于刷新列表等外部状态）。
  final VoidCallback? onAdded;

  /// 以对话框形式打开。
  static Future<void> show(
    BuildContext context, {
    required int parentWordId,
    required String term,
    required RelationType relation,
    VoidCallback? onAdded,
  }) => showDialog<void>(
    context: context,
    builder: (context) => RelatedWordDialog(
      parentWordId: parentWordId,
      term: term,
      relation: relation,
      onAdded: onAdded,
    ),
  );

  @override
  ConsumerState<RelatedWordDialog> createState() => _RelatedWordDialogState();
}

class _RelatedWordDialogState extends ConsumerState<RelatedWordDialog> {
  RelatedWordPreview? _preview;
  String? _message;
  String? _error;
  bool _busy = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// 检查该词在词库中的状态。
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await ref
          .read(wordDetailActionsProvider)
          .previewRelatedWord(widget.parentWordId, widget.term);
      if (!mounted) return;
      setState(() => _preview = preview);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = normalizeError(error).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 加入词库（必要时同时排初始化任务）。
  ///
  /// 加入后重新读一次预览：状态区要立刻从「尚未加入」变成「排队中」，
  /// 加入按钮也要随之消失——不刷新的话用户会以为没生效而连点几次。
  Future<void> _add() async {
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(wordDetailActionsProvider)
          .addRelatedWord(
            parentWordId: widget.parentWordId,
            term: widget.term,
            relation: widget.relation,
          );
      if (!mounted) return;
      setState(() => _message = _messageOf(result));
      widget.onAdded?.call();
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = normalizeError(error).message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// 加入结果的提示文案。
  String _messageOf(RelatedAddResult result) {
    if (!result.queued) return '该词条已在词库中且内容可用，无需重复内容补全。';
    return result.created ? '已加入词库并排入内容补全队列。' : '已排入内容补全队列。';
  }

  /// 跳到该词条的详情页。
  ///
  /// 先取到路由再关弹窗：关掉之后本组件的 `context` 已经失效，
  /// 再去 `GoRouter.of(context)` 会抛「找不到 Provider」。
  void _openWord(int wordId) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('$wordDetailPathPrefix$wordId');
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: _Title(relation: widget.relation, term: widget.term),
      content: SizedBox(
        width: relatedWordDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (preview?.translation != null)
              Text(
                preview!.translation!,
                style: LexiType.body.copyWith(
                  color: context.lexiColors.secondaryLabel,
                ),
              ),
            if (preview?.difference != null)
              _DifferenceBlock(text: preview!.difference!),
            if (_busy && preview == null) const _CheckingRow(),
            if (preview != null) _StatusBlock(preview: preview),
            if (_message != null) _MessageBlock(text: _message!),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: LexiSpace.s8),
                child: Text(
                  _error!,
                  style: LexiType.footnote.copyWith(
                    color: context.lexiColors.dangerText,
                  ),
                ),
              ),
            const SizedBox(height: LexiSpace.s12),
            _Actions(
              preview: preview,
              adding: _adding,
              onOpenWord: _openWord,
              onAdd: _add,
            ),
          ],
        ),
      ),
    );
  }
}

/// 标题：关系徽标 + 词形。
class _Title extends StatelessWidget {
  const new({required this.relation, required this.term});

  final RelationType relation;
  final String term;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        LexiBadge(label: relationLabel(relation), tone: LexiBadgeTone.purple),
        const SizedBox(height: LexiSpace.s8),
        Text(
          term,
          style: LexiType.title2.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 「正在检查词库状态…」。
class _CheckingRow extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LexiSpace.s20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const SizedBox(
            width: LexiSpace.s16,
            height: LexiSpace.s16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: LexiSpace.s10),
          Text(
            '正在检查词库状态…',
            style: LexiType.body.copyWith(
              color: context.lexiColors.secondaryLabel,
            ),
          ),
        ],
      ),
    );
  }
}

/// 区别说明高亮块。
class _DifferenceBlock extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: LexiSpace.s8),
      padding: const EdgeInsets.all(LexiSpace.s10),
      decoration: BoxDecoration(
        color: colors.purple.withValues(alpha: LexiTint.tint),
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Text(
        text,
        style: LexiType.body.copyWith(color: colors.purpleText),
      ),
    );
  }
}

/// 词库状态、语言方向与词性。
class _StatusBlock extends StatelessWidget {
  const new({required this.preview});

  final RelatedWordPreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final existing = preview.existing;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: LexiSpace.s10),
      padding: const EdgeInsets.all(LexiSpace.s12),
      decoration: BoxDecoration(
        color: colors.label.withValues(alpha: LexiTint.group),
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Column(
        children: <Widget>[
          _StatusRow(
            label: '词库状态',
            value: existing == null
                ? const _PlainBadge(text: '尚未加入')
                : InitializationBadge(status: existing.initializationStatus),
          ),
          _StatusRow(
            label: '语言方向',
            value: Text(
              '${languageLabel(preview.sourceLanguage)} → '
              '${languageLabel(preview.targetLanguage)}',
              style: LexiType.body.copyWith(color: colors.label),
            ),
          ),
          if (preview.partOfSpeech != null)
            _StatusRow(
              label: '词性',
              value: Text(
                preview.partOfSpeech!,
                style: LexiType.body.copyWith(color: colors.label),
              ),
            ),
          if (existing != null)
            _StatusRow(
              label: '掌握度',
              value: MasteryBadge(
                level: existing.masteryLevel,
                score: existing.masteryScore,
              ),
            ),
        ],
      ),
    );
  }
}

/// 状态区的一行。
class _StatusRow extends StatelessWidget {
  const new({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LexiSpace.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: LexiType.body.copyWith(
              color: context.lexiColors.secondaryLabel,
            ),
          ),
          value,
        ],
      ),
    );
  }
}

/// 无状态徽标。
class _PlainBadge extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => LexiBadge(label: text);
}

/// 成功提示块。
class _MessageBlock extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: LexiSpace.s8),
      padding: const EdgeInsets.all(LexiSpace.s10),
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: LexiTint.tint),
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Text(
        text,
        style: LexiType.body.copyWith(color: colors.successText),
      ),
    );
  }
}

/// 底部按钮：打开词条 / 加入词库。
class _Actions extends StatelessWidget {
  const new({
    required this.preview,
    required this.adding,
    required this.onOpenWord,
    required this.onAdd,
  });

  final RelatedWordPreview? preview;
  final bool adding;
  final ValueChanged<int> onOpenWord;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final existing = preview?.existing;
    final canAdd = preview?.canAdd ?? false;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        if (existing != null) ...<Widget>[
          OutlinedButton(
            onPressed: adding ? null : () => onOpenWord(existing.id),
            child: const Text('打开词条'),
          ),
          const SizedBox(width: LexiSpace.s8),
        ],
        if (canAdd)
          FilledButton(
            onPressed: adding || preview == null ? null : onAdd,
            child: Text(existing == null ? '加入词库并内容补全' : '加入内容补全'),
          ),
      ],
    );
  }
}
