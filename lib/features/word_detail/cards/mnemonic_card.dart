/// 助记与句子分析卡片。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 助记与句子分析卡片：助记法、发音提示、常见错误与句子分析。
///
/// 调用方保证 [learning] 与 [analysis] 至少一个非空，否则整卡不显示。
class MnemonicCard extends ConsumerWidget {
  /// 以词条 ID、学习信息与句子分析构造。
  const new({
    required this.wordId,
    required this.learning,
    required this.analysis,
    super.key,
  });

  /// 词条 ID；生成助记的任务靠它入队。
  final int wordId;

  /// 学习辅助信息。
  final LearningView learning;

  /// 句子分析。
  final SentenceAnalysisView analysis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: '助记与句子分析',
      icon: Icons.lightbulb_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (learning.pronunciationTip != null)
            DetailField(label: '发音提示', value: learning.pronunciationTip!),
          if (learning.mnemonic != null)
            DetailField(label: '助记', value: learning.mnemonic!),
          if (learning.commonMistakes.isNotEmpty)
            _BulletGroup(
              title: '常见错误',
              items: <String>[for (final item in learning.commonMistakes) item],
            ),
          _MnemonicAction(
            wordId: wordId,
            hasMnemonic: learning.mnemonic != null,
          ),
          if (!analysis.isEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _AnalysisSection(analysis: analysis),
          ],
        ],
      ),
    );
  }
}

/// 「生成助记 / 重新生成助记」按钮。
///
/// **旧版没有这个入口**：`JobTaskType.mnemonic` 一直存在，但只有 worker
/// 在初始化末尾自动补投一次——初始化早就跑完的词条因此永远拿不到助记。
class _MnemonicAction extends ConsumerStatefulWidget {
  const new({required this.wordId, required this.hasMnemonic});

  final int wordId;
  final bool hasMnemonic;

  @override
  ConsumerState<_MnemonicAction> createState() => _MnemonicActionState();
}

class _MnemonicActionState extends ConsumerState<_MnemonicAction> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _busy ? null : _request,
        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
        label: Text(widget.hasMnemonic ? '重新生成助记' : 'AI 生成助记'),
      ),
    );
  }

  Future<void> _request() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(wordDetailActionsProvider).requestMnemonic(widget.wordId);
      messenger.showSnackBar(const SnackBar(content: Text('已加入生成队列')));
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
    if (mounted) setState(() => _busy = false);
  }
}

class _AnalysisSection extends StatelessWidget {
  const new({required this.analysis});

  final SentenceAnalysisView analysis;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Divider(color: colors.separator, height: 18),
        if (analysis.grammarPattern != null)
          DetailField(label: '语法模式', value: analysis.grammarPattern!),
        if (analysis.grammarExplanation != null)
          DetailField(label: '语法解释', value: analysis.grammarExplanation!),
        _BulletGroup(title: '语法要点', items: analysis.grammarNotes),
        _ItemGroup(title: '关键表达', items: analysis.keyExpressions),
        _ItemGroup(title: '相似例句', items: analysis.similarExamples),
        _BulletGroup(
          title: '句式变换',
          items: <String>[
            for (final item in analysis.variations)
              if (item.label == null)
                item.text
              else
                '${item.label}：${item.text}',
          ],
        ),
      ],
    );
  }
}

/// 带附注的条目组（关键表达 / 相似例句）。
///
/// 这两类条目的附注各有各的含义（关键表达是中文含义 + 用法提示，
/// 相似例句是译文 + 讲解重点），因此逐条渲染而不是拍平成纯文本列表——
/// 拍平会让这两类最有价值的补充信息在界面上消失。
class _ItemGroup extends StatelessWidget {
  const new({required this.title, required this.items});

  final String title;
  final List<SentenceAnalysisItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: colors.secondaryLabel,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          for (final item in items) DetailBullet(item.text, note: _note(item)),
        ],
      ),
    );
  }

  /// 把该条目所有非空附注按「标签：内容」拼起来。
  String? _note(SentenceAnalysisItem item) {
    final parts = <String>[
      if (item.meaning != null) '含义：${item.meaning}',
      if (item.translation != null) '译文：${item.translation}',
      if (item.focus != null) '重点：${item.focus}',
      if (item.note != null) '提示：${item.note}',
    ];
    return parts.isEmpty ? null : parts.join('\n');
  }
}

class _BulletGroup extends StatelessWidget {
  const new({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: colors.secondaryLabel,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          for (final item in items) DetailBullet(item),
        ],
      ),
    );
  }
}
