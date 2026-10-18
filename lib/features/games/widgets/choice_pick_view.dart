/// 听音辨词（LISTENING_PICK）与词义冲刺（MEANING_BLITZ）的渲染层。
///
/// 对应旧版 `app/(main)/games/page.tsx` 第 297-310 行的两段内联题面：
/// 两者共用同一个 `ChoiceGrid`，只在题面上分叉——听音辨词给一个可重复点击的
/// 大喇叭按钮，词义冲刺给一行大字英文词条。
///
/// **朗读规则与旧版逐条一致**：进入每一题后延迟 [gameAutoSpeakDelayMs]
/// 自动播一次（每题只播一次，由 `_spokenItemId` 记住），听音辨词另有
/// 可重复点击的喇叭按钮，点任一选项也会把该词条读一遍。
///
/// **与旧版的差异**：旧版点错后靠 `setTimeout` 清红框，界面自己管状态；
/// 这里红框、锁定与耗时全在 `ChoicePickState` 里，视图只做两件事——
/// 把状态画出来、把点击翻译成动作。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/games/choice_pick.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/features/games/game_speech.dart';
import 'package:lexiloop/features/games/widgets/game_choice_grid.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 听音辨词 / 词义冲刺视图。
class ChoicePickView extends ConsumerStatefulWidget {
  /// 以状态与派发回调构造。
  const new({required this.state, required this.onAction, super.key});

  /// 状态机状态。
  final ChoicePickState state;

  /// 动作派发。
  final ValueChanged<Object> onAction;

  @override
  ConsumerState<ChoicePickView> createState() => _ChoicePickViewState();
}

class _ChoicePickViewState extends ConsumerState<ChoicePickView> {
  Timer? _autoSpeakTimer;

  /// 已经自动播过的题目 ID（旧版 `autoPlayedRef`）。
  int? _spokenItemId;

  @override
  void initState() {
    super.initState();
    _scheduleAutoSpeak();
  }

  @override
  void didUpdateWidget(ChoicePickView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.current?.itemId != widget.state.current?.itemId) {
      _scheduleAutoSpeak();
    }
  }

  @override
  void dispose() {
    _autoSpeakTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.state.current;
    if (question == null) return const SizedBox.shrink();
    final listening = widget.state.core.plan.mode == GameMode.listeningPick;
    return Column(
      children: <Widget>[
        if (listening)
          _ListeningPrompt(onSpeak: () => _speak(question.word.term))
        else
          _MeaningPrompt(term: question.word.term),
        const SizedBox(height: LexiSpace.s20),
        GameChoiceGrid(
          choices: question.choices.options,
          enabled: !widget.state.isLocked,
          stateOf: (choice) => _choiceState(choice, question),
          // 听音辨词把释义作为选项副标题（旧版 `ChoiceGrid` 传
          // `choiceDefinitions`）；词义冲刺的选项本身就是释义，不传。
          subtitleOf: listening
              ? (choice) => question.choices.definitions[choice] ?? ''
              : null,
          onChoose: _choose,
        ),
      ],
    );
  }

  /// 选项的三态：点对的选项变绿，点错的变红，其余不动。
  ChoiceState _choiceState(String choice, GameQuestion question) {
    if (widget.state.solved && choice == question.answer) {
      return ChoiceState.correct;
    }
    return widget.state.wrongChoice == choice
        ? ChoiceState.wrong
        : ChoiceState.idle;
  }

  /// 每题只自动播一次；换题时由 [didUpdateWidget] 再排一次。
  void _scheduleAutoSpeak() {
    final question = widget.state.current;
    if (question == null || _spokenItemId == question.itemId) return;
    _spokenItemId = question.itemId;
    _autoSpeakTimer?.cancel();
    _autoSpeakTimer = Timer(
      const Duration(milliseconds: gameAutoSpeakDelayMs),
      () => _speak(question.word.term),
    );
  }

  /// 点选项：先朗读再判题（旧版 `chooseAnswer` 的第一句就是 `playCachedTts`）。
  void _choose(String choice) {
    final question = widget.state.current;
    if (question != null) _speak(question.word.term);
    widget.onAction(PickChoice(choice));
  }

  void _speak(String term) {
    unawaited(ref.read(gameSpeakerProvider)(term));
  }
}

class _ListeningPrompt extends StatelessWidget {
  const new({required this.onSpeak});

  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      children: <Widget>[
        Text(
          '听发音，选择正确的英文词条',
          style: LexiType.body.copyWith(color: colors.quaternaryLabel),
        ),
        const SizedBox(height: LexiSpace.s14),
        // 纯图标控件必须自带标签：读屏软件否则只会念「按钮」，
        // 桌面端用户悬停也看不到它做什么。`Tooltip` 同时提供悬停提示
        // 与语义标签，一处覆盖两端。
        Tooltip(
          message: '播放发音',
          child: Material(
            color: colors.accent.withValues(alpha: LexiTint.tint),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onSpeak,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: _speakButtonSize,
                height: _speakButtonSize,
                child: Icon(
                  LucideIcons.volume2,
                  size: 44,
                  color: colors.accent,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: LexiSpace.s8),
        Text(
          '点击可重复播放',
          style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
        ),
      ],
    );
  }
}

class _MeaningPrompt extends StatelessWidget {
  const new({required this.term});

  final String term;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      children: <Widget>[
        Text(
          '选择最准确的中文释义',
          style: LexiType.body.copyWith(color: colors.quaternaryLabel),
        ),
        const SizedBox(height: LexiSpace.s16),
        Text(
          term,
          textAlign: TextAlign.center,
          style: LexiType.hero.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

/// 发音按钮的点击热区边长（方形）。
const double _speakButtonSize = 92;
