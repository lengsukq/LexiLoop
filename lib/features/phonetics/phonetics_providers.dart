/// 音标训练页面的状态与提供者。
///
/// 结构与 `games_providers.dart` / `match_providers.dart` 一致：
/// 准备 → 进行中 → 结算中 → 完成 / 失败。
/// 朗读由界面层的 `_SpeakButton` 直接调用 [ttsServiceProvider]，
/// 不经过控制器——TTS 是平台能力，失败信息属于界面反馈，
/// 混进游戏状态机会让「保存失败」与「朗读失败」难以区分。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/phonetics/quiz.dart';
import 'package:lexiloop/features/games/game_ticker.dart';
import 'package:lexiloop/features/games/games_providers.dart';
import 'package:lexiloop/services/game_service.dart';
import 'package:lexiloop/services/phonetic_service.dart';

/// 答对后展示解析的停留时长（毫秒，旧版 `CORRECT_FEEDBACK_MS`）。
const int phoneticCorrectFeedbackMs = 1200;

/// 音标训练编排服务。
final Provider<PhoneticService> phoneticServiceProvider =
    Provider<PhoneticService>(
      (ref) => PhoneticService(
        ref.watch(studyDaoProvider),
        ref.watch(gameDaoProvider),
      ),
    );

/// 音标页状态。
sealed class PhoneticState {
  /// 供子类继承。
  const new();
}

/// 准备阶段。
final class PhoneticSetup extends PhoneticState {
  /// 以各字段构造。
  const new({this.accent = Accent.us, this.loading = false, this.error});

  /// 口音。
  final Accent accent;

  /// 是否正在组题。
  final bool loading;

  /// 上一次开局的错误提示。
  final String? error;
}

/// 进行中。
final class PhoneticPlaying extends PhoneticState {
  /// 以各字段构造。
  const new({required this.session, required this.quiz});

  /// 会话数据。
  final PhoneticSession session;

  /// 训练状态。
  final PhoneticQuizState quiz;
}

/// 结算中。
final class PhoneticSaving extends PhoneticState {
  /// 以字段构造。
  const new({required this.previous});

  /// 结算前的一局。
  final PhoneticPlaying previous;
}

/// 结算完成。
final class PhoneticFinished extends PhoneticState {
  /// 以字段构造。
  const new({required this.result});

  /// 结算结果。
  final GameResult result;
}

/// 保存失败。
final class PhoneticSaveFailed extends PhoneticState {
  /// 以各字段构造。
  const new({required this.message, required this.previous});

  /// 提示文案。
  final String message;

  /// 结算前的一局。
  final PhoneticPlaying previous;
}

/// 音标训练控制器。
class PhoneticController extends Notifier<PhoneticState> {
  late final GameTicker _ticker = GameTicker(_onTick);
  Timer? _continueTimer;

  @override
  PhoneticState build() {
    ref.onDispose(_stopAll);
    return const PhoneticSetup();
  }

  /// 选择口音。
  void selectAccent(Accent accent) {
    final current = state;
    if (current is! PhoneticSetup) return;
    state = PhoneticSetup(accent: accent);
  }

  /// 开始一局。
  Future<void> start() async {
    final current = state;
    if (current is! PhoneticSetup) return;
    final accent = current.accent;
    _stopAll();
    state = PhoneticSetup(accent: accent, loading: true);
    try {
      final session = await ref
          .read(phoneticServiceProvider)
          .start(accent: accent, now: _now());
      final quiz = startPhoneticQuiz(
        plan: session.plan,
        questions: session.questions,
      );
      state = PhoneticPlaying(
        session: session,
        quiz: phoneticQuizNext(quiz, const StartPhoneticQuiz()),
      );
      _ticker.start();
    } on Object catch (error) {
      state = PhoneticSetup(
        accent: accent,
        error: normalizeError(error).message,
      );
    }
  }

  /// 派发训练动作。
  void dispatch(PhoneticQuizAction action) {
    final current = state;
    if (current is! PhoneticPlaying) return;
    final quiz = phoneticQuizNext(current.quiz, action);
    state = PhoneticPlaying(session: current.session, quiz: quiz);
    _syncQuiz(quiz);
  }

  /// 退出到准备页。
  void exit() {
    _stopAll();
    state = const PhoneticSetup();
  }

  /// 重试结算。
  Future<void> retrySave() async {
    final current = state;
    if (current is! PhoneticSaveFailed) return;
    await _finish(current.previous);
  }

  /// 结算失败后回到训练继续。
  void resumeAfterSaveFailure() {
    final current = state;
    if (current is! PhoneticSaveFailed) return;
    state = current.previous;
    _ticker.start();
  }

  void _onTick(int deltaMs) => dispatch(TickPhoneticQuiz(deltaMs));

  /// 答对后自动进入下一题；跳过则等用户看完解析再继续。
  void _syncQuiz(PhoneticQuizState quiz) {
    if (quiz.core.isFinished) {
      final current = state;
      if (current is PhoneticPlaying) unawaited(_finish(current));
      return;
    }
    final question = quiz.current;
    final answeredCorrectly =
        question != null && quiz.revealed && quiz.selected == question.answer;
    if (answeredCorrectly && _continueTimer == null) {
      _continueTimer = Timer(
        const Duration(milliseconds: phoneticCorrectFeedbackMs),
        () {
          _continueTimer = null;
          dispatch(const ContinuePhonetic());
        },
      );
    }
  }

  Future<void> _finish(PhoneticPlaying playing) async {
    _stopAll();
    state = PhoneticSaving(previous: playing);
    try {
      final result = await ref
          .read(phoneticServiceProvider)
          .complete(session: playing.session, state: playing.quiz, now: _now());
      state = PhoneticFinished(result: result);
    } on Object catch (error) {
      state = PhoneticSaveFailed(
        message: normalizeError(error).message,
        previous: playing,
      );
    }
  }

  void _stopAll() {
    _ticker.stop();
    _continueTimer?.cancel();
    _continueTimer = null;
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;
}

/// 音标页状态提供者。
final NotifierProvider<PhoneticController, PhoneticState>
phoneticControllerProvider =
    NotifierProvider<PhoneticController, PhoneticState>(PhoneticController.new);
