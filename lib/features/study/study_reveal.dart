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

  /// 当前词条已存的助记与构词信息；未加载或为空时不展示。
  final StudyRevealContent? revealContent;

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
          _TermLine(word: item.word, accent: accent),
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
          if (revealContent case final content?
              when !content.isEmpty) ...<Widget>[
            const SizedBox(height: LexiSpace.s8),
            DisclosureSection(
              title: '助记与构词',
              child: _RevealContentBlock(content: content),
            ),
          ],
        ],
      ),
    );
  }

  /// 句子类词条的「例句」往往就是题干本身，不再重复。
  bool get _showExample =>
      item.word.contentType != LexicalContentType.sentence &&
      item.word.examples.isNotEmpty;
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

/// 词条 + 音标 + 朗读。
class _TermLine extends StatelessWidget {
  const new({required this.word, required this.accent});

  final StudyWordView word;
  final Accent accent;

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
