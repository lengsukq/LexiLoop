/// 小游戏页面的状态与提供者。
///
/// **为什么要有控制器**：旧版 `games/page.tsx`（543 行）用 12 个 `useState`
/// 加 3 个 `useRef` 管理同一局游戏，倒计时、连击、逐题记录、结算重试
/// 互相纠缠，任何一处改动都可能让「分数」与「提交的作答」不一致。
/// 这里把「一局的生命周期」收敛成一个状态机：
/// `准备 → 进行中 → 结算中 → 结算完成 / 保存失败`，
/// 每个状态各自持有它需要的数据，界面只做 `when` 分支。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/game_dao.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_runtime.dart';
import 'package:lexiloop/services/game_service.dart';

/// 倒计时刷新间隔（毫秒）。
///
/// 10Hz 足够让进度条看起来连续，又不会让每帧都重建整棵树。
const int gameTickMs = 100;

/// 答对/答错后的反馈停留时长（毫秒）。
const int gameFeedbackMs = 450;

/// 游戏 DAO。
final Provider<GameDao> gameDaoProvider = Provider<GameDao>(
  (ref) => GameDao(ref.watch(databaseProvider)),
);

/// 小游戏编排服务。
final Provider<GameService> gameServiceProvider = Provider<GameService>(
  (ref) => GameService(
    ref.watch(studyDaoProvider),
    ref.watch(reviewServiceProvider),
    ref.watch(gameDaoProvider),
  ),
);

/// 游戏页的状态。
sealed class GamesState {
  /// 供子类继承。
  const new();
}

/// 准备阶段（含加载中与错误提示）。
final class GamesSetup extends GamesState {
  /// 以各字段构造。
  const new({
    this.selectedMode = GameMode.whackAMole,
    this.loadingMode,
    this.error,
  });

  /// 当前选中的模式。
  final GameMode selectedMode;

  /// 正在加载的模式；`null` 表示空闲。
  final GameMode? loadingMode;

  /// 上一次开局失败的提示。
  final String? error;
}

/// 进行中。
final class GamesPlaying extends GamesState {
  /// 以各字段构造。
  const new({required this.session, required this.runtime});

  /// 会话数据。
  final GameSession session;

  /// 运行态。
  final GameRuntime runtime;

  /// 计分内核。
  GameCoreState get core => runtime.core;
}

/// 结算中。
final class GamesSaving extends GamesState {
  /// 以字段构造。
  const new({required this.previous});

  /// 结算前的一局（失败时用于重试）。
  final GamesPlaying previous;
}

/// 结算完成。
final class GamesFinished extends GamesState {
  /// 以各字段构造。
  const new({required this.result, required this.outcomes});

  /// 结算结果。
  final GameResult result;

  /// 逐题结果（顺序与题目一致）。
  final List<GameOutcome> outcomes;
}

/// 保存失败。
final class GamesSaveFailed extends GamesState {
  /// 以各字段构造。
  const new({required this.message, required this.previous});

  /// 面向用户的提示。
  final String message;

  /// 结算前的一局。
  final GamesPlaying previous;
}

/// 小游戏控制器。
class GamesController extends Notifier<GamesState> {
  Timer? _ticker;
  Timer? _advanceTimer;
  final Stopwatch _stopwatch = Stopwatch();
  int _lastElapsedMs = 0;

  @override
  GamesState build() {
    ref.onDispose(_stopAll);
    return const GamesSetup();
  }

  /// 选择模式（不开始）。
  void selectMode(GameMode mode) {
    final current = state;
    if (current is! GamesSetup) return;
    state = GamesSetup(selectedMode: mode);
  }

  /// 开始一局。
  Future<void> start(GameMode mode) async {
    _stopAll();
    state = GamesSetup(selectedMode: mode, loadingMode: mode);
    try {
      final session = await ref
          .read(gameServiceProvider)
          .start(mode: mode, now: _now());
      final runtime = startGameRuntime(
        mode: mode,
        plan: session.plan,
        questions: session.questions,
        random: math.Random().nextDouble,
      );
      state = GamesPlaying(session: session, runtime: runtime);
      _startTicker();
    } on Object catch (error) {
      state = GamesSetup(
        selectedMode: mode,
        error: normalizeError(error).message,
      );
    }
  }

  /// 派发一个状态机动作。
  void dispatch(Object action) {
    final current = state;
    if (current is! GamesPlaying) return;
    final runtime = current.runtime.dispatch(action) ?? current.runtime;
    state = GamesPlaying(session: current.session, runtime: runtime);
    _syncRuntime(runtime);
  }

  /// 退出当前一局，回到准备页。
  void exit() {
    _stopAll();
    state = const GamesSetup();
  }

  /// 重试结算。
  Future<void> retrySave() async {
    final current = state;
    if (current is! GamesSaveFailed) return;
    await _finish(current.previous);
  }

  /// 结算失败后回到本局继续玩。
  void resumeAfterSaveFailure() {
    final current = state;
    if (current is! GamesSaveFailed) return;
    state = current.previous;
    _startTicker();
  }

  /// 时间增量由真实时钟给出，避免应用卡顿时倒计时变慢。
  void _startTicker() {
    _stopwatch
      ..reset()
      ..start();
    _lastElapsedMs = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(milliseconds: gameTickMs),
      (_) => _onTick(),
    );
  }

  void _onTick() {
    final current = state;
    if (current is! GamesPlaying) return;
    final elapsed = _stopwatch.elapsedMilliseconds;
    final delta = elapsed - _lastElapsedMs;
    _lastElapsedMs = elapsed;
    if (delta <= 0) return;
    dispatch(tickActionFor(current.session.mode, delta));
  }

  /// 一局结束后同步外部状态：结束则结算，判定完成则安排自动推进。
  void _syncRuntime(GameRuntime runtime) {
    if (runtime.core.isFinished) {
      final current = state;
      if (current is GamesPlaying) unawaited(_finish(current));
      return;
    }
    if (runtime.awaitingAdvance && _advanceTimer == null) {
      final mode = (state as GamesPlaying).session.mode;
      _advanceTimer = Timer(const Duration(milliseconds: gameFeedbackMs), () {
        _advanceTimer = null;
        dispatch(advanceActionFor(mode));
      });
    }
  }

  Future<void> _finish(GamesPlaying playing) async {
    _stopAll();
    state = GamesSaving(previous: playing);
    final core = playing.runtime.core;
    final questions = playing.session.questions;
    try {
      final result = await ref
          .read(gameServiceProvider)
          .complete(
            session: playing.session,
            summary: core.summary,
            answers: core.answerRecords(questions),
            now: _now(),
          );
      state = GamesFinished(
        result: result,
        outcomes: <GameOutcome>[
          for (final question in questions) core.outcomeFor(question.itemId),
        ],
      );
    } on Object catch (error) {
      state = GamesSaveFailed(
        message: normalizeError(error).message,
        previous: playing,
      );
    }
  }

  void _stopAll() {
    _ticker?.cancel();
    _ticker = null;
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _stopwatch.stop();
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;
}

/// 游戏页状态提供者。
final NotifierProvider<GamesController, GamesState> gamesControllerProvider =
    NotifierProvider<GamesController, GamesState>(GamesController.new);
