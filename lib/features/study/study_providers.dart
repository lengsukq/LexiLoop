/// 学习会话的状态与数据提供者。
///
/// 控制器只做**编排**：调 `StudyService` 开始/跳过、调 `ReviewService`
/// 提交作答，再把最新的 [StudySessionView] 放回状态。判题、FSRS 调度、
/// 熟练度全部留在服务层——界面层重复哪怕一条规则，双端就会漂移。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/duration.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';
import 'package:lexiloop/services/study_service.dart';

/// 活跃计时器的构造工厂。
///
/// 用 provider 暴露工厂而不是让页面直接 `StudyClock()`：widget 测试必须注入
/// 与 `tester.pump` 同步的假时钟（`binding.clock`），否则 `Timer` 走假时间、
/// `DateTime.now()` 走真实时间，「45 秒空闲」这条规则根本构造不出来。
typedef StudyClockFactory = StudyClock Function();

/// 活跃计时器的构造工厂。
final Provider<StudyClockFactory> studyClockFactoryProvider =
    Provider<StudyClockFactory>((ref) => StudyClock.new);

/// 读取某词条四档评级的间隔预览。
typedef IntervalPreviewLoader = Future<List<FsrsIntervalPreview>> Function(
  int wordId,
);

/// 间隔预览的读取入口。
///
/// 抽成 provider 是为了给「预览失败」留一个稳定的注入点：界面必须在预览
/// 抛错时照常作答，而真实的 `ReviewService` 几乎不会在只读查询上失败。
/// 闭包捕获服务实例而不是 `ref`，provider 被回收后它仍然可用。
final Provider<IntervalPreviewLoader> intervalPreviewLoaderProvider =
    Provider<IntervalPreviewLoader>((ref) {
      final service = ref.watch(reviewServiceProvider);
      return (wordId) => service.previewIntervals(
        wordId,
        now: DateTime.now().millisecondsSinceEpoch,
      );
    });

/// 读取当前词条已存的助记、词根与词缀。
///
/// 单独作为按需 loader：会话 SQL 只加载答题必需字段，不为整场题目读取扩展 JSON。
typedef StudyRevealContentLoader = Future<StudyRevealContent> Function(
  int wordId,
);

/// 学习揭示内容读取入口。
final Provider<StudyRevealContentLoader> studyRevealContentLoaderProvider =
    Provider<StudyRevealContentLoader>((ref) {
      final dao = ref.watch(wordDetailDaoProvider);
      return dao.studyRevealContent;
    });

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
  /// [durationMs] 由界面层的活跃计时器给出（已经扣掉暂停与空闲）；
  /// 为空时退回「题目展示时刻到现在」的墙钟估算。
  ///
  /// 提交后重新读取会话（而不是本地改计数）：`resumeIndex`、正确/错误计数、
  /// 自适应追问插入的新题都由数据库决定，本地推算一定会和服务层不一致。
  Future<ReviewOutcome?> submit({
    required ReviewRating rating,
    String? userAnswer,
    int? durationMs,
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
            durationMs: boundedActiveDurationMs(
              durationMs ?? _wallClockMs(now),
            ),
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

  /// 界面层没有给出活跃时长时的墙钟兜底。
  ///
  /// 这里**只**算「现在 - 题目展示时刻」，不夹上界：夹取统一由
  /// [boundedActiveDurationMs] 负责，两处都夹会让「到底是谁改了我的时长」
  /// 无从追查。崩溃恢复与时钟回拨这两条路径会走到这里。
  int? _wallClockMs(int now) {
    final shownAt = _itemShownAt;
    if (shownAt == null) return null;
    return now - shownAt;
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
