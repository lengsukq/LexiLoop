/// 揭示答案后的判定面板。
///
/// 这里是「回答正确 / 回答错误 / 参考答案」唯一出现的地方，且出现在**自评
/// 之前**：用户先看到客观判题与正确答案，再决定这次记得怎么样。旧版把
/// 「回答正确」与「自评：忘了」并排放在提交后的卡片里，读起来像一个自相
/// 矛盾的判定（见 `docs/FLUTTER_PARITY.md` 的答题流程一节）。
///
/// 面板是只读的：自评、提交与前进都在 `study_page.dart` 编排。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/answer_evaluator.dart';
import 'package:lexiloop/features/study/study_answer_diff.dart';
import 'package:lexiloop/features/study/study_hint_bar.dart';
import 'package:lexiloop/features/study/study_prompt.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 揭示答案后的判定与词条内容。
class StudyRevealPanel extends StatelessWidget {
  /// 以题目、本地预览、用户作答、是否用过提示与口音构造。
  const new({
    required this.item,
    required this.preview,
    required this.answer,
    required this.usedHint,
    required this.accent,
    this.revealContent,
    this.onOpenDetail,
    super.key,
  });

  /// 当前题目。
  final StudyItemView item;

  /// 与服务判题同源的只读预览。
  final AnswerPreview preview;

  /// 用户实际给出的答案文本。
  final String answer;

  /// 本题是否用过提示。
  final bool usedHint;

  /// 设置中的默认发音口音。
  final Accent accent;

  /// 当前词条已存的助记、构词、易混词与句法信息；未加载或为空时不展示。
  final StudyRevealContent? revealContent;

  /// 跳转词条详情页的回调；无路由上下文时为空。
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final correct = preview.isCorrect;
    final tone = correct == null
        ? colors.accentText
        : correct
        ? colors.successText
        : colors.dangerText;
    final icon = correct == null
        ? LucideIcons.bookOpen
        : correct
        ? LucideIcons.circleCheck
        : LucideIcons.circleX;
    final hintDowngraded = studyHintDowngrades(
      item,
      answer,
      usedHint: usedHint,
    );
    final showDiff = correct == false && studyAnswerDiffApplies(item);

    return Surface(
      key: const Key('study.reveal'),
      variant: SurfaceVariant.inset,
      padding: const EdgeInsets.all(LexiSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _VerdictRow(correct: correct, icon: icon, tone: tone),
          const SizedBox(height: LexiSpace.s12),
          _TermLine(
            word: item.word,
            accent: accent,
            onOpenDetail: onOpenDetail,
          ),
          if (studyMeaningText(item.word) case final meaning
              when meaning.isNotEmpty) ...<Widget>[
            const SizedBox(height: LexiSpace.s8),
            Text(meaning, style: LexiType.body.copyWith(color: colors.label)),
          ],
          if (showDiff) ...<Widget>[
            const SizedBox(height: LexiSpace.s12),
            StudyAnswerDiff(
              item: item,
              expectedAnswer: preview.expectedAnswer,
              answer: answer,
              isCorrect: false,
            ),
          ],
          if (hintDowngraded) ...<Widget>[
            const SizedBox(height: LexiSpace.s8),
            Text(
              studyHintRevealedText,
              style: LexiType.footnote.copyWith(color: colors.warningText),
            ),
          ],
          if (_showExample) ...<Widget>[
            const SizedBox(height: LexiSpace.s8),
            DisclosureSection(
              title: '例句',
              child: _ExampleBlock(example: item.word.examples.first),
            ),
          ],
          if (revealContent case final content? when !content.isEmpty)
            _RevealExtras(content: content),
        ],
      ),
    );
  }

  /// 句子类词条的「例句」往往就是题干本身，不再重复。
  bool get _showExample =>
      item.word.contentType != LexicalContentType.sentence &&
      item.word.examples.isNotEmpty;
}

/// 扩展揭示区：助记与构词、易混词辨析、句法解析（按需折叠展示）。
class _RevealExtras extends StatelessWidget {
  const new({required this.content});

  final StudyRevealContent content;

  bool get _hasMorphology =>
      content.mnemonic != null ||
      content.roots.isNotEmpty ||
      content.affixes.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_hasMorphology) ...<Widget>[
          const SizedBox(height: LexiSpace.s8),
          DisclosureSection(
            title: '助记与构词',
            child: _RevealContentBlock(content: content),
          ),
        ],
        if (content.confusedWords.isNotEmpty) ...<Widget>[
          const SizedBox(height: LexiSpace.s8),
          DisclosureSection(
            title: '易混词辨析',
            child: _ConfusedWordsBlock(items: content.confusedWords),
          ),
        ],
        if (!content.sentenceAnalysis.isEmpty) ...<Widget>[
          const SizedBox(height: LexiSpace.s8),
          DisclosureSection(
            title: '句法解析',
            child: _SentenceAnalysisBlock(analysis: content.sentenceAnalysis),
          ),
        ],
      ],
    );
  }
}

/// 易混词列表。
class _ConfusedWordsBlock extends StatelessWidget {
  const new({required this.items});

  final List<RelatedWordView> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < items.length; i += 1) ...<Widget>[
          if (i > 0) const SizedBox(height: LexiSpace.s6),
          Text(
            items[i].translation == null
                ? items[i].word
                : '${items[i].word} · ${items[i].translation}',
            style: LexiType.body.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (items[i].difference case final diff? when diff.isNotEmpty)
            Text(
              diff,
              style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
            ),
        ],
      ],
    );
  }
}

/// 句子语法结构与要点。
class _SentenceAnalysisBlock extends StatelessWidget {
  const new({required this.analysis});

  final SentenceAnalysisView analysis;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (analysis.grammarPattern case final pattern? when pattern.isNotEmpty)
          Text(
            '句型：$pattern',
            style: LexiType.body.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (analysis.grammarExplanation case final exp?
            when exp.isNotEmpty) ...<Widget>[
          const SizedBox(height: LexiSpace.s4),
          Text(
            exp,
            style: LexiType.body.copyWith(color: colors.secondaryLabel),
          ),
        ],
        for (final note in analysis.grammarNotes) ...<Widget>[
          const SizedBox(height: LexiSpace.s4),
          Text(
            '• $note',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
        ],
      ],
    );
  }
}

/// 已存助记与构词信息；仅作轻量补充，不参与答题流程。
class _RevealContentBlock extends StatelessWidget {
  const new({required this.content});

  final StudyRevealContent content;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final mnemonic = content.mnemonic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (mnemonic != null) ...<Widget>[
          Text(
            '助记',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s4),
          Text(mnemonic, style: LexiType.body.copyWith(color: colors.label)),
        ],
        if (content.roots.isNotEmpty) ...<Widget>[
          if (mnemonic != null) const SizedBox(height: LexiSpace.s8),
          Text(
            '词根',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s4),
          for (final root in content.roots)
            Text(
              root.meaning == null
                  ? root.root
                  : '${root.root} · ${root.meaning}',
              style: LexiType.body.copyWith(color: colors.label),
            ),
        ],
        if (content.affixes.isNotEmpty) ...<Widget>[
          if (mnemonic != null || content.roots.isNotEmpty)
            const SizedBox(height: LexiSpace.s8),
          Text(
            '词缀',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s4),
          for (final affix in content.affixes)
            Text(
              affix.meaning == null
                  ? affix.value
                  : '${affix.value} · ${affix.meaning}',
              style: LexiType.body.copyWith(color: colors.label),
            ),
        ],
      ],
    );
  }
}

/// 判定行：图标 + 文案。
class _VerdictRow extends StatelessWidget {
  const new({required this.correct, required this.icon, required this.tone});

  final bool? correct;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: tone),
        const SizedBox(width: LexiSpace.s8),
        Text(
          studyVerdictText(isCorrect: correct),
          style: LexiType.title.copyWith(
            color: tone,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 词条 + 音标 + 朗读 + 可选详情入口。
class _TermLine extends StatelessWidget {
  const new({required this.word, required this.accent, this.onOpenDetail});

  final StudyWordView word;
  final Accent accent;
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final phonetic = studyPhonetic(word, accent);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                word.term,
                style: LexiType.title2.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (phonetic != null) ...<Widget>[
                const SizedBox(height: LexiSpace.s4),
                Text(
                  '/$phonetic/',
                  style: LexiType.footnote.copyWith(
                    color: colors.secondaryLabel,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onOpenDetail != null)
          IconButton(
            key: const Key('study.openWordDetail'),
            tooltip: '查看词条详情',
            onPressed: onOpenDetail,
            icon: Icon(
              LucideIcons.externalLink,
              size: 17,
              color: colors.secondaryLabel,
            ),
          ),
        SpeakButton(word: word, accent: accent),
      ],
    );
  }
}

/// 第一条例句。
class _ExampleBlock extends StatelessWidget {
  const new({required this.example});

  final ExampleView example;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final translation = example.translation?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          example.sentence,
          style: LexiType.body.copyWith(
            color: colors.secondaryLabel,
            fontStyle: FontStyle.italic,
          ),
        ),
        if (translation != null && translation.isNotEmpty) ...<Widget>[
          const SizedBox(height: LexiSpace.s4),
          Text(
            translation,
            style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
          ),
        ],
      ],
    );
  }
}
