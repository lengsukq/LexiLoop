/// 配对页面的状态与提供者。
///
/// 与 `games_providers.dart` 同构：准备 → 进行中 → 结算中 → 完成 / 失败。
/// 之所以不合并成一个控制器：配对的「进行中」持有的是牌面状态
/// （[MatchBoardState]）而不是题目状态机，两者的动作集合没有交集，
/// 硬合并只会得到一个到处是 `is` 判断的巨型控制器。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/games/matching.dart';
import 'package:lexiloop/features/games/game_ticker.dart';
import 'package:lexiloop/features/games/games_providers.dart';
import 'package:lexiloop/services/game_service.dart';
import 'package:lexiloop/services/matching_service.dart';

/// 错配闪烁的停留时长（毫秒，旧版硬编码 460）。
const int matchFlashMs = 460;

/// 一个配对预设（旧版 `PRESETS`）。
class MatchPreset {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.name,
    required this.pairs,
    required this.seconds,
    required this.description,
  });

  /// 稳定标识。
  final String id;

  /// 名称。
  final String name;

  /// 词汇组数。
  final int pairs;

  /// 限时（秒）。
  final int seconds;

  /// 说明。
  final String description;
}

/// 三个预设。
const List<MatchPreset> matchPresets = <MatchPreset>[
  MatchPreset(
    id: 'relaxed',
    name: '轻松热身',
    pairs: 5,
    seconds: 90,
    description: '词少、时间充足',
  ),
  MatchPreset(
    id: 'standard',
    name: '标准挑战',
    pairs: 6,
    seconds: 60,
    description: '适合每日练习',
  ),
  MatchPreset(
    id: 'sprint',
    name: '极速冲刺',
    pairs: 8,
    seconds: 45,
    description: '高强度限时配对',
  ),
];

/// 默认预设（旧版取 `PRESETS[1]`）。
const MatchPreset defaultMatchPreset = MatchPreset(
  id: 'standard',
  name: '标准挑战',
  pairs: 6,
  seconds: 60,
  description: '适合每日练习',
);

/// 配对编排服务。
final Provider<MatchingService> matchingServiceProvider =
    Provider<MatchingService>(
      (ref) => MatchingService(
        ref.watch(studyDaoProvider),
        ref.watch(reviewServiceProvider),
        ref.watch(gameDaoProvider),
      ),
    );

/// 配对页状态。
sealed class MatchState {
  /// 供子类继承。
  const new();
}

/// 准备阶段。
final class MatchSetup extends MatchState {
  /// 以各字段构造。
  const new({
    this.preset = defaultMatchPreset,
    this.loading = false,
    this.error,
  });

  /// 当前预设。
  final MatchPreset preset;

  /// 是否正在组题。
  final bool loading;

  /// 上一次开局的错误提示。
  final String? error;
}

/// 进行中。
final class MatchPlaying extends MatchState {
  /// 以各字段构造。
  const new({required this.session, required this.board});

  /// 会话数据。
  final GameSession session;

  /// 牌面状态。
  final MatchBoardState board;
}

/// 结算中。
final class MatchSaving extends MatchState {
  /// 以字段构造。
  const new({required this.previous});

  /// 结算前的一局。
  final MatchPlaying previous;
}

/// 结算完成。
final class MatchFinished extends MatchState {
  /// 以字段构造。
  const new({required this.result});

  /// 结算结果。
  final GameResult result;
}

/// 保存失败。
final class MatchSaveFailed extends MatchState {
  /// 以各字段构造。
  const new({required this.message, required this.previous});

  /// 提示文案。
  final String message;

  /// 结算前的一局。
  final MatchPlaying previous;
}

/// 配对控制器。
class MatchController extends Notifier<MatchState> {
  late final GameTicker _ticker = GameTicker(_onTick);
  Timer? _flashTimer;

  @override
  MatchState build() {
    ref.onDispose(_stopAll);
    return const MatchSetup();
  }

  /// 选择预设。
  void selectPreset(MatchPreset preset) {
    final current = state;
    if (current is! MatchSetup) return;
    state = MatchSetup(preset: preset);
  }

  /// 开始一局。
  Future<void> start() async {
    final current = state;
    if (current is! MatchSetup) return;
    final preset = current.preset;
    _stopAll();
    state = MatchSetup(preset: preset, loading: true);
    try {
      final session = await ref
          .read(matchingServiceProvider)
          .start(
            pairCount: preset.pairs,
            durationSeconds: preset.seconds,
            now: _now(),
          );
      final board = startMatchingBoard(
        plan: session.plan,
        pairs: session.questions,
        random: math.Random().nextDouble,
      );
      final started = matchBoardNext(board, const StartMatch());
      state = MatchPlaying(session: session, board: started);
      _ticker.start();
    } on Object catch (error) {
      state = MatchSetup(preset: preset, error: normalizeError(error).message);
    }
  }

  /// 派发牌面动作。
  void dispatch(MatchAction action) {
    final current = state;
    if (current is! MatchPlaying) return;
    final board = matchBoardNext(current.board, action);
    state = MatchPlaying(session: current.session, board: board);
    _syncBoard(board);
  }

  /// 退出到准备页。
  void exit() {
    _stopAll();
    state = const MatchSetup();
  }

  /// 重试结算。
  Future<void> retrySave() async {
    final current = state;
    if (current is! MatchSaveFailed) return;
    await _finish(current.previous);
  }

  /// 结算失败后回到牌面继续。
  void resumeAfterSaveFailure() {
    final current = state;
    if (current is! MatchSaveFailed) return;
    state = current.previous;
    _ticker.start();
  }

  void _onTick(int deltaMs) {
    final current = state;
    if (current is! MatchPlaying) return;
    dispatch(TickMatch(deltaMs));
  }

  /// 牌面锁定期间安排解锁，全部配对后结算。
  void _syncBoard(MatchBoardState board) {
    if (board.core.isFinished) {
      final current = state;
      if (current is MatchPlaying) unawaited(_finish(current));
      return;
    }
    if (board.feedback.isLocked && _flashTimer == null) {
      _flashTimer = Timer(const Duration(milliseconds: matchFlashMs), () {
        _flashTimer = null;
        dispatch(const ClearMatchFlash());
      });
    }
  }

  Future<void> _finish(MatchPlaying playing) async {
    _stopAll();
    state = MatchSaving(previous: playing);
    try {
      final result = await ref
          .read(matchingServiceProvider)
          .complete(
            session: playing.session,
            state: playing.board,
            now: _now(),
          );
      state = MatchFinished(result: result);
    } on Object catch (error) {
      state = MatchSaveFailed(
        message: normalizeError(error).message,
        previous: playing,
      );
    }
  }

  void _stopAll() {
    _ticker.stop();
    _flashTimer?.cancel();
    _flashTimer = null;
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;
}

/// 配对页状态提供者。
final NotifierProvider<MatchController, MatchState> matchControllerProvider =
    NotifierProvider<MatchController, MatchState>(MatchController.new);
