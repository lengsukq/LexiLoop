/// 学习会话的题干区域。
///
/// 题干按题型分四种形态：给英文词条、给中文释义、只给听音、给挖空句。
/// 四种形态各自独立成一个小组件，而不是在一个 `build()` 里堆 switch——
/// 旧版 `study-client.tsx` 497 行的直接教训就是把「按题型分支」和
/// 「作答逻辑」写在了同一个函数里。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_speech.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 朗读按钮的边长（逻辑像素），同时满足触控热区下限。
const double _speakButtonSize = 44;

/// 题干卡片。
class StudyPrompt extends StatelessWidget {
  /// 以题目与设置中的默认口音构造。
  const new({required this.item, required this.accent, super.key});

  /// 当前题目。
  final StudyItemView item;

  /// 设置中的默认发音口音，用于挑选音标。
  final Accent accent;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      showSpecular: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _PromptHeader(type: item.questionType),
          const SizedBox(height: 12),
          _body(context),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) => switch (item.questionType) {
    QuestionType.enToZh ||
    QuestionType.enToZhChoice => _TermPrompt(word: item.word, accent: accent),
    QuestionType.listeningChoice || QuestionType.listeningSpelling =>
      _ListeningPrompt(word: item.word, accent: accent),
    QuestionType.clozeSentence => _ClozePrompt(
      cloze: item.cloze,
      word: item.word,
    ),
    QuestionType.zhToEnChoice ||
    QuestionType.zhToEnSpelling ||
    QuestionType.letterBank => _MeaningPrompt(word: item.word),
  };
}

/// 题头：题型标签。
class _PromptHeader extends StatelessWidget {
  const new({required this.type});

  final QuestionType type;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Text(
        studyQuestionTypeLabel(type),
        style: LexiType.caption.copyWith(
          color: colors.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 给英文词条的题干：词条 + 音标 + 朗读。
class _TermPrompt extends StatelessWidget {
  const new({required this.word, required this.accent});

  final StudyWordView word;
  final Accent accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final phonetic = studyPhonetic(word, accent);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                word.term,
                style: LexiType.display.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              if (phonetic != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  '/$phonetic/',
                  style: LexiType.callout.copyWith(
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

/// 给中文释义的题干。
class _MeaningPrompt extends StatelessWidget {
  const new({required this.word});

  final StudyWordView word;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final meaning = studyMeaningText(word);
    return Text(
      meaning.isEmpty ? '（该词条暂无释义）' : meaning,
      style: LexiType.page.copyWith(
        color: colors.label,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// 只给听音的题干。
class _ListeningPrompt extends StatelessWidget {
  const new({required this.word, required this.accent});

  /// 待朗读的词条。
  final StudyWordView word;

  /// 设置中的默认发音口音。
  final Accent accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        SpeakButton(word: word, accent: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '听音作答',
                style: LexiType.title2.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '听不清时可以再点一次朗读',
                style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 例句填空的题干：挖空句 + 释义与翻译提示。
class _ClozePrompt extends StatelessWidget {
  const new({required this.cloze, required this.word});

  final ClozePayload? cloze;
  final StudyWordView word;

  @override
  Widget build(BuildContext context) {
    final payload = cloze;
    if (payload == null) return _MeaningPrompt(word: word);

    final colors = context.lexiColors;
    final style = LexiType.title.copyWith(color: colors.label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(_clozeSpan(payload.blankedSentence, style, colors.accent)),
        if (payload.translation case final translation?) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            translation,
            style: LexiType.body.copyWith(color: colors.secondaryLabel),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          '提示：${studyMeaningText(word)}',
          style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
        ),
      ],
    );
  }
}

/// 把挖空句渲染成「普通文本 + 下划线空位」。
///
/// 用 `Text.rich` 而不是 `RichText`：渲染结果相同，但 `Text` 保留了整段
/// 纯文本，widget 测试里的 `find.textContaining` 才能断言空位确实在句子里。
TextSpan _clozeSpan(String blanked, TextStyle style, Color blankColor) {
  final parts = blanked.split(clozeBlankToken);
  final spans = <TextSpan>[];
  for (var index = 0; index < parts.length; index += 1) {
    if (index > 0) {
      spans.add(
        TextSpan(
          text: clozeBlankToken,
          style: style.copyWith(
            color: blankColor,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationThickness: 2,
          ),
        ),
      );
    }
    spans.add(TextSpan(text: parts[index], style: style));
  }
  return TextSpan(children: spans);
}

/// 朗读按钮。
///
/// 走 [speakStudyWord]：真人录音（词典 mp3）优先、系统朗读兜底，与旧版
/// `playCachedTts` 的策略一致。降级与失败都会在界面上提示——Android 缺语音包
/// 时系统 TTS 会静默无声，让按钮「点了没反应」是最难排查的形态。
class SpeakButton extends ConsumerWidget {
  /// 以要朗读的词条与口音构造。
  const new({required this.word, required this.accent, super.key});

  /// 待朗读的词条；语速按内容类型区分。
  final StudyWordView word;

  /// 设置中的默认发音口音；真人录音与系统朗读都按它选。
  final Accent accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    return SizedBox(
      width: _speakButtonSize,
      height: _speakButtonSize,
      child: IconButton(
        onPressed: () =>
            unawaited(speakStudyWord(context, ref, word: word, accent: accent)),
        tooltip: '朗读',
        iconSize: 20,
        icon: Icon(Icons.volume_up_rounded, color: colors.accent),
      ),
    );
  }
}
