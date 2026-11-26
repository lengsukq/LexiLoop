/// 初始化任务的后台维护。
///
/// 对应汇报文档 §5 的接线缺口：`InitializationWorker` 已实现、有测试，
/// 但没有任何地方构造它，导致导入词条入队后永远没人处理。
///
/// **为什么是个独立类而不是直接写在 `main()` 里**：
/// 1. `main()` 是应用入口，只负责「走完三步再挂 Timer」；重试退避、
///    重入保护、错误吞没这些策略属于可测的业务逻辑，不能塞进 `main`；
/// 2. 测试无法启动整个应用，但可以构造这个类直接断言策略。
/// 对应旧版：服务端由常驻进程 + 定时任务驱动；本地单进程改用 Timer。
library;

// `unawaited` 来自 dart:async，定时器本身已搬到 one_shot_timer.dart。
import 'dart:async';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/services/initialization/job_runner.dart';
import 'package:lexiloop/services/scheduling/one_shot_timer.dart';

/// 后台一批跑完后回调，入参是这一批实际处理的任务数。
///
/// 存在的理由与旧版的 `BACKGROUND_TICK_EVENT` 相同：队列页拿不到执行器，
/// 只能靠「后台跑完了」这个信号来刷新，而不是自己轮询。
/// 传 0 表示这批无事可做，监听方应据此跳过刷新。
typedef MaintenanceTickListener = void Function(int processed);

/// 后台维护的配置。
class MaintenancePolicy {
  /// 以各字段构造。
  const new({
    this.tickInterval = const Duration(milliseconds: maintenanceIntervalMs),
    this.busyTickInterval = const Duration(
      milliseconds: maintenanceBusyIntervalMs,
    ),
    this.runInitialCleanup = true,
    this.runStaleDataCleanup = true,
  });

  /// 空闲时的 `tick` 间隔（队列已排空后的保活节奏）。
  final Duration tickInterval;

  /// 上一批确实处理了任务时的 `tick` 间隔。
  final Duration busyTickInterval;

  /// 启动时是否先做一次崩溃恢复（收回 RUNNING 任务）。
  final bool runInitialCleanup;

  /// 启动时是否顺带回收两类「长期没人管」的历史数据
  /// （错词本衰减、卡死的导入批次）。
  final bool runStaleDataCleanup;

  /// 上一批处理了 [processed] 个任务后，下一批该等多久。
  ///
  /// **刻意写成纯函数**：调度器只负责照着算好的时长排期，
  /// 「忙则快、空则慢」这条规则因此能脱离定时器单测。
  Duration intervalAfter({required int processed}) =>
      processed > 0 ? busyTickInterval : tickInterval;
}

/// 封装「启动 → 定时推进」的维护调度。
///
/// 构造即完成依赖装配，不自动启动；[start] 负责走完三步并挂 Timer：
/// 1. `resetStaleRunningJobs(now)` —— 收回上次崩溃遗留的 RUNNING 任务；
/// 2. `retryFailedJobs(now)` —— 收回冷却到期的失败任务；
/// 3. `tick(now)` —— 按优先级处理一批（受 `defaultMaxJobsPerTick` 限量）。
///
/// 定时器不是 `Timer.periodic`，而是每批结束后按 [MaintenancePolicy.intervalAfter]
/// 重新排一次：处理量不同，下一批该等多久也不同。
///
/// [dispose] 取消定时器，对应 `ProviderScope` 释放或测试结束。
class InitializationMaintenance {
  /// 以执行器与可选策略构造。
  ///
  /// `clock` 与 `timerFactory` 是可测性接缝：默认读系统时钟、挂真实
  /// `Timer`；测试传入假的时钟与假的定时器后，整条排期链路不需要等待。
  new(
    this._runner, [
    this._policy = const MaintenancePolicy(),
    this._clock = _wallClockMs,
    this._timerFactory = createRealMaintenanceTimer,
  ]);

  final InitializationJobRunner _runner;
  final MaintenancePolicy _policy;
  final int Function() _clock;
  final MaintenanceTimerFactory _timerFactory;

  final List<MaintenanceTickListener> _listeners = <MaintenanceTickListener>[];
  MaintenanceTimer? _timer;
  bool _running = false;
  bool _paused = false;
  bool _ticking = false;
  bool _kickPending = false;

  /// 是否已启动且尚未 [dispose]。
  bool get isRunning => _running;

  /// 是否已暂停（例如应用切入后台）。
  bool get isPaused => _paused;

  /// 订阅「后台一批跑完」事件。
  ///
  /// 队列页靠它自动刷新；重复订阅会收到多次通知，故调用方要保证只订阅一次。
  void addTickListener(MaintenanceTickListener listener) {
    _listeners.add(listener);
  }

  /// 取消订阅；未订阅过也安全。
  void removeTickListener(MaintenanceTickListener listener) {
    _listeners.remove(listener);
  }

  /// 启动：做一次恢复 + 失败回收 + 历史数据回收 + 首批处理，然后挂上定时器。
  ///
  /// 可重复调用；第二次调用直接返回，不会挂第二个 Timer。
  Future<void> start({required int now}) async {
    if (_running) return;
    _running = true;
    _paused = false;
    await _reclaimJobs(now);
    await _sweepStaleData(now);
    final processed = await _tickAndReport();
    // 上面三步都是 await，期间可能已被 dispose 或 pause；此时不该把定时器复活。
    if (!_running || _paused) return;
    _schedule(_policy.intervalAfter(processed: processed));
  }

  /// 立即唤醒队列（例如导入或手动添加新词条后，不必等空闲间隔）。
  ///
  /// 未启动或已暂停时为安全空操作（避免在无 `MaintenanceBootstrap` 的测试里挂出定时器）。
  void kick() {
    if (!_running || _paused) return;
    if (_ticking) {
      _kickPending = true;
      return;
    }
    _timer?.cancel();
    _timer = null;
    unawaited(_tickThenReschedule());
  }

  /// 暂停后台调度（应用切入后台时停止定时器，节省电量）。
  void pause() {
    if (!_running || _paused) return;
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  /// 恢复后台调度（应用回到前台时立即检查一次并继续排期）。
  void resume() {
    if (!_running || !_paused) return;
    _paused = false;
    unawaited(_tickThenReschedule());
  }

  /// 只做一次 `tick(now)`（队列页「立即处理」按钮走这里）。
  ///
  /// 错误被吞掉而不是上抛：维护是后台行为，不应在用户主动点的按钮上
  /// 以异常形式暴露；真正的失败记录在任务的 `last_error` 里。
  ///
  /// 不发「后台跑完」通知也不影响排期——它不是调度器自己发起的那一批。
  Future<int> pumpOnce({required int now}) async {
    if (_ticking) return 0;
    _ticking = true;
    try {
      return await _runner.tick(now: now);
    } on Object {
      return 0;
    } finally {
      _ticking = false;
    }
  }

  /// 取消定时器，之后 [start] 可以重新点火。
  void dispose() {
    _running = false;
    _paused = false;
    _kickPending = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 崩溃恢复与失败重排。两步都只是「收拾残局」，失败不该让应用起不来。
  Future<void> _reclaimJobs(int now) async {
    try {
      if (_policy.runInitialCleanup) {
        await _runner.resetStaleRunningJobs(now);
      }
      await _runner.retryFailedJobs(now);
    } on Object {
      // 只影响这一轮的回收，用户仍可在队列页手动触发。
    }
  }

  /// 错词本衰减 + 卡死的导入批次过期。
  ///
  /// 同样按「失败不阻塞启动」处理：这两步是数据整洁度问题，
  /// 缺一次只会让错词本多留几天条目，不会让功能不可用。
  Future<void> _sweepStaleData(int now) async {
    if (!_policy.runStaleDataCleanup) return;
    try {
      await _runner.decayStaleWrongWords(now);
      await _runner.expireStaleImportBatches(now);
    } on Object {
      // 见 [_reclaimJobs] 的说明。
    }
  }

  /// 跑一批并通知监听者，返回处理数量。
  ///
  /// 兼作重入保护：上一批还没跑完时直接返回 0。
  /// `tick` 是顺序执行的串行操作；定时器到期与用户点「立即处理」可能并发，
  /// 而 Drift 的 SQLite 连接是单线程写入的，并发 `tick` 会互相锁住。
  /// 简单的布尔锁足够——维护不需要排队，最坏不过是少跑一批。
  Future<int> _tickAndReport() async {
    if (_ticking) return 0;
    _ticking = true;
    try {
      final processed = await _runner.tick(now: _clock());
      _notify(processed);
      return processed;
    } on Object {
      // 后台 tick 失败只记录不抛：真正的错误已写入任务的 last_error，
      // 上抛只会导致 Timer 回调里出现未捕获异常。
      return 0;
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tickThenReschedule() async {
    final processed = await _tickAndReport();
    if (!_running || _paused) return;
    if (_kickPending) {
      _kickPending = false;
      _schedule(_policy.busyTickInterval);
      return;
    }
    _schedule(_policy.intervalAfter(processed: processed));
  }

  void _schedule(Duration interval) {
    _timer?.cancel();
    _timer = _timerFactory(interval, _onTimerElapsed);
  }

  void _onTimerElapsed() {
    if (!_running || _paused) return;
    unawaited(_tickThenReschedule());
  }

  /// 先复制再回调：监听方可能在回调里取消自己的订阅。
  void _notify(int processed) {
    for (final listener in List<MaintenanceTickListener>.of(_listeners)) {
      listener(processed);
    }
  }
}

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;
