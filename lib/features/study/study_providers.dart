/// 学习会话的状态与数据提供者。
///
/// 控制器只做**编排**：调 `StudyService` 开始/跳过、调 `ReviewService`
/// 提交作答，再把最新的 [StudySessionView] 放回状态。判题、FSRS 调度、
/// 熟练度全部留在服务层——界面层重复哪怕一条规则，双端就会漂移。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/services/study_service.dart';

/// 学习会话控制器。
class StudySessionController extends AsyncNotifier<StudySessionView?> {
  /// 当前题目的展示时刻（epoch 毫秒），用于估算作答耗时。
  int? _itemShownAt;

  @override
  Future<StudySessionView?> build() async => null;

  /// 开始（或恢复）一次学习会话。
  ///
  /// [StudyService.startSession] 默认 `resume: true`：中途退出应用是常态，
  /// 每次重新抽题会让「今天学了什么」变得不可预期。
  Future<void> start(StudyMode mode, {bool continuous = false}) async {
    state = const AsyncValue<StudySessionView?>.loading();
    state = await AsyncValue.guard<StudySessionView?>(() async {
      final now = _now();
      final session = await ref
          .read(studyServiceProvider)
          .startSession(mode: mode, now: now, continuous: continuous);
      _itemShownAt = now;
      return session;
    });
  }

  /// 提交当前题目的作答；没有待答题目时返回 `null`。
  ///
  /// 提交后重新读取会话（而不是本地改计数）：`resumeIndex`、正确/错误计数、
  /// 自适应追问插入的新题都由数据库决定，本地推算一定会和服务层不一致。
  Future<ReviewOutcome?> submit({
    required ReviewRating rating,
    String? userAnswer,
  }) async {
    final session = state.value;
    final item = session?.currentItem;
    if (session == null || item == null) return null;

    final now = _now();
    final outcome = await ref
        .read(reviewServiceProvider)
        .processAnswer(
          AnswerInput(
            clientAnswerId: _nextAnswerId(session.id, item.itemId),
            wordId: item.word.id,
            rating: rating,
            questionType: item.questionType,
            studySessionId: session.id,
            studySessionItemId: item.itemId,
            userAnswer: userAnswer,
            durationMs: _elapsedMs(now),
          ),
          now: now,
        );
    await _reload(session.id);
    return outcome;
  }

  /// 跳过当前题目。
  ///
  /// 不传原因，走 [StudyService.skipItem] 的默认值 `LATER`（显式传同一个值
  /// 会触发 `avoid_redundant_argument_values`）。跳过会进候选排除窗口，让
  /// 这个词在冷却期内不再出现；用系统原因（如 `SESSION_EXPIRED`）会绕过
  /// 排除，把刚跳过的词立刻塞回来。
  Future<void> skip() async {
    final session = state.value;
    final item = session?.currentItem;
    if (session == null || item == null) return;

    final now = _now();
    final view = await ref
        .read(studyServiceProvider)
        .skipItem(sessionId: session.id, itemId: item.itemId, now: now);
    state = AsyncValue<StudySessionView?>.data(view);
    _itemShownAt = now;
  }

  /// 清空会话状态（离开学习页或开始新一轮时调用）。
  void reset() {
    _itemShownAt = null;
    state = const AsyncValue<StudySessionView?>.data(null);
  }

  /// 重新读取会话，刷新题目状态与待答下标。
  Future<void> _reload(int sessionId) async {
    state = await AsyncValue.guard<StudySessionView?>(
      () => ref.read(studyDaoProvider).loadSession(sessionId),
    );
    _itemShownAt = _now();
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// 本题已耗费的毫秒数。
  ///
  /// 上限复用 [maxActiveAnswerDurationMs]：应用挂起后恢复时，
  /// 「现在 - 题目展示时刻」会变成几小时，直接入库会把平均耗时与
  /// 掌握度一起算歪。
  int? _elapsedMs(int now) {
    final shownAt = _itemShownAt;
    if (shownAt == null) return null;
    return (now - shownAt).clamp(0, maxActiveAnswerDurationMs);
  }

  /// 生成一次性的幂等键。
  ///
  /// 必须**每次作答都不同**：固定值会让第二次作答命中幂等分支，服务层
  /// 直接回显旧结果、FSRS 不再推进，界面上表现为「点了没反应」。
  String _nextAnswerId(int sessionId, int itemId) =>
      '$sessionId-$itemId-${DateTime.now().microsecondsSinceEpoch}';
}

/// 当前学习会话。
final AsyncNotifierProvider<StudySessionController, StudySessionView?>
studySessionProvider =
    AsyncNotifierProvider<StudySessionController, StudySessionView?>(
      StudySessionController.new,
    );
