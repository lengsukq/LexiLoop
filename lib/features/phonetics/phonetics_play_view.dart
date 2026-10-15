/// 音标训练进行中的页面。
///
/// 结构：HUD → 题面（听音 / 音标 / 单词）→ 朗读按钮 → 选项 → 解析 → 跳过。
/// 音标符号用大字号等宽字体展示；朗读**真的**调用 [ttsServiceProvider]，
/// 读的是示例词而不是 IPA 符号——系统 TTS 读不出 IPA，这是旧版踩过的坑。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/phonetics/catalog.dart';
import 'package:lexiloop/domain/phonetics/quiz.dart';
import 'package:lexiloop/domain/phonetics/selection.dart';
import 'package:lexiloop/features/games/widgets/game_choice_grid.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/features/phonetics/phonetics_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 音标训练进行中页面。
class PhoneticPlayView extends StatelessWidget {
  /// 以进行中状态与回调构造。
  const new({
    required this.playing,
    required this.onAction,
    required this.onExit,
    super.key,
  });

  /// 进行中状态。
  final PhoneticPlaying playing;

  /// 动作派发。
  final ValueChanged<PhoneticQuizAction> onAction;

  /// 退出回调。
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final quiz = playing.quiz;
    final question = quiz.current;
    if (question == null) return const SizedBox.shrink();
    return Column(
      children: <Widget>[
        GameHud(title: '音标辨音训练', core: quiz.core, onExit: onExit),
        const SizedBox(height: LexiSpace.s12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                _Prompt(question: question, quiz: quiz),
                const SizedBox(height: LexiSpace.s16),
                GameChoiceGrid(
                  choices: question.base.choices.options,
                  onChoose: (choice) => onAction(ChoosePhonetic(choice)),
                  stateOf: (choice) => _stateOf(quiz, question, choice),
                  subtitleOf:
                      question.challenge == PhoneticChallengeType.phoneticToWord
                      ? (choice) =>
                            question.base.choices.definitions[choice] ?? ''
                      : null,
                  promptStyle: _optionStyle(context, question),
                  enabled: !quiz.revealed && !quiz.hasWrongSelection,
                ),
                if (quiz.hasWrongSelection) ...<Widget>[
                  const SizedBox(height: LexiSpace.s10),
                  Text(
                    '不对，再听一次后重新选择',
                    style: LexiType.body.copyWith(
                      color: context.lexiColors.danger,
                    ),
                  ),
                ],
                if (quiz.revealed) ...<Widget>[
                  const SizedBox(height: LexiSpace.s14),
                  _Analysis(entry: question.entry),
                  const SizedBox(height: LexiSpace.s12),
                  FilledButton(
                    onPressed: () => onAction(const ContinuePhonetic()),
                    child: const Text('继续'),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: LexiSpace.s12),
                  TextButton(
                    onPressed: () => onAction(const SkipPhonetic()),
                    child: const Text('跳过这题'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  ChoiceState _stateOf(
    PhoneticQuizState quiz,
    PhoneticQuestion question,
    String choice,
  ) {
    if (quiz.revealed && choice == question.answer) return ChoiceState.correct;
    if (quiz.selected == choice && choice != question.answer) {
      return ChoiceState.wrong;
    }
    return ChoiceState.idle;
  }

  TextStyle _optionStyle(BuildContext context, PhoneticQuestion question) {
    // 两个分支的字号原本是 19 与 16，都落在 `title` 档（17），
    // 因此条件已无意义——保留条件只会让人以为它们不一样。
    final base = TextStyle(
      color: context.lexiColors.label,
      fontSize: LexiType.title.fontSize,
      fontWeight: FontWeight.w600,
    );
    return question.challenge.hasPhoneticChoices
        ? base.copyWith(fontFamily: 'monospace')
        : base;
  }
}

class _Prompt extends StatelessWidget {
  const new({required this.question, required this.quiz});

  final PhoneticQuestion question;
  final PhoneticQuizState quiz;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.xl),
      padding: const EdgeInsets.symmetric(
        vertical: LexiSpace.s20,
        horizontal: LexiSpace.s16,
      ),
      child: Column(
        children: <Widget>[
          Text(
            _hint(question.challenge),
            style: LexiType.footnote.copyWith(color: colors.quaternaryLabel),
          ),
          const SizedBox(height: LexiSpace.s10),
          _Body(question: question),
          const SizedBox(height: LexiSpace.s12),
          _SpeakButton(term: question.base.word.term),
        ],
      ),
    );
  }

  String _hint(PhoneticChallengeType challenge) => switch (challenge) {
    PhoneticChallengeType.soundToPhonetic => '听发音，选择正确音标',
    PhoneticChallengeType.phoneticToWord => '看音标，选择对应单词',
    PhoneticChallengeType.wordToPhonetic => '看单词，选择正确音标',
  };
}

class _Body extends StatelessWidget {
  const new({required this.question});

  final PhoneticQuestion question;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return switch (question.challenge) {
      PhoneticChallengeType.phoneticToWord => Text(
        question.sound.phonetic,
        style: LexiType.hero.copyWith(
          color: colors.accent,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
        ),
      ),
      PhoneticChallengeType.wordToPhonetic => Column(
        children: <Widget>[
          Text(
            question.base.word.term,
            style: LexiType.display.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: LexiSpace.s4),
          Text(
            question.base.word.definition,
            textAlign: TextAlign.center,
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
        ],
      ),
      PhoneticChallengeType.soundToPhonetic => Text(
        question.base.word.definition,
        textAlign: TextAlign.center,
        style: LexiType.body.copyWith(color: colors.secondaryLabel),
      ),
    };
  }
}

/// 朗读按钮：真的调用系统 TTS，失败时在按钮下方给出中文提示。
class _SpeakButton extends ConsumerStatefulWidget {
  const new({required this.term});

  final String term;

  @override
  ConsumerState<_SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends ConsumerState<_SpeakButton> {
  String? _error;
  bool _busy = false;

  Future<void> _speak() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = await ref.read(settingsServiceProvider).load();
      await ref
          .read(ttsServiceProvider)
          .speakTerm(
            term: widget.term,
            sourceLanguage: 'en',
            contentType: LexicalContentType.word,
            playback: settings.playback,
          );
    } on Object catch (error) {
      final message = normalizeError(
        error,
        fallback: AppErrorCode.ttsUnavailable,
      ).message;
      if (mounted) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      children: <Widget>[
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _speak,
          icon: const Icon(Icons.volume_up_rounded, size: 18),
          label: Text(_busy ? '朗读中…' : '朗读示例词'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: LexiSpace.s6),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: LexiType.caption.copyWith(color: colors.danger),
            ),
          ),
      ],
    );
  }
}

/// 解析面板：发音要领 + 口型 + 易混音标对比。
class _Analysis extends StatelessWidget {
  const new({required this.entry});

  final PhonemeEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final confusables = confusablePhonemes(entry.symbol);
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(LexiSpace.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                entry.display,
                style: LexiType.title2.copyWith(
                  color: colors.accent,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: LexiSpace.s8),
              Text(
                '${entry.nameZh} · ${entry.identity.groupLabel}',
                style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
              ),
            ],
          ),
          const SizedBox(height: LexiSpace.s8),
          _Field(label: '发音要领', text: entry.description),
          _Field(label: '口型', text: entry.guide.mouthShape),
          _Field(label: '易踩坑', text: entry.relations.pitfalls),
          if (confusables.isNotEmpty)
            _Field(
              label: '易混音标',
              text: confusables
                  .map(
                    (item) =>
                        '${item.display} ${item.nameZh}（${item.description}）',
                  )
                  .join('\n'),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const new({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(top: LexiSpace.s6),
      child: RichText(
        text: TextSpan(
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          children: <InlineSpan>[
            TextSpan(
              text: '$label：',
              style: TextStyle(
                color: colors.label,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }
}
