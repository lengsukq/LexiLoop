/// 后台维护调度的策略测试。
///
/// 这里不碰数据库：被测对象是「什么时候跑、跑几批、失败怎么办」，
/// 用假执行器断言调用序列即可。真实 worker 的行为由
/// `test/services/initialization_worker_test.dart` 覆盖。
///
/// 排期一律走 [FakeScheduler] 手动触发，不用等墙钟——
/// 真实定时器会让「空闲 10 分钟 / 忙 30 秒」这种断言没法写。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/services/initialization/initialization_maintenance.dart';
import 'package:lexiloop/services/initialization/job_runner.dart';
// 定时器接缝已搬到独立文件：初始化维护与远程备份共用同一个一次性定时器。
import 'package:lexiloop/services/scheduling/one_shot_timer.dart';

/// 假执行器要抛出的异常。
class FakeFailure implements Exception {
  /// 以说明构造。
  new(this.message);

  /// 说明文本。
  final String message;

  @override
  String toString() => 'FakeFailure: $message';
}

/// 记录调用序列的假执行器。
class RecordingRunner implements InitializationJobRunner {
  /// 依次记录的方法名。
  final List<String> calls = <String>[];

  /// [tick] 的返回值。
  ///
  /// 默认 0（空闲）：有产出的批次会把下一次间隔压到 `MaintenancePolicy.busyTickInterval`，
  /// 想测长间隔的用例用默认值即可。
  int tickResult = 0;

  /// 让所有方法抛出。
  Exception? failWith;

  /// 阻塞 [tick]，用于构造并发场景。
  Completer<void>? tickGate;

  int _concurrentTicks = 0;
  int _maxConcurrentTicks = 0;

  /// 观察到的最大并发 tick 数。
  int get maxConcurrentTicks => _maxConcurrentTicks;

  @override
  Future<int> tick({required int now}) async {
    calls.add('tick');
    _concurrentTicks += 1;
    if (_concurrentTicks > _maxConcurrentTicks) {
      _maxConcurrentTicks = _concurrentTicks;
    }
    final gate = tickGate;
    if (gate != null) await gate.future;
    _concurrentTicks -= 1;
    final failure = failWith;
    if (failure != null) throw failure;
    return tickResult;
  }

  @override
  Future<int> resetStaleRunningJobs(int now, {bool staleOnly = false}) async {
    calls.add('reset(staleOnly: $staleOnly)');
    final failure = failWith;
    if (failure != null) throw failure;
    return 0;
  }

  @override
  Future<int> retryFailedJobs(int now) async {
    calls.add('retryFailed');
    final failure = failWith;
    if (failure != null) throw failure;
    return 0;
  }

  @override
  Future<int> decayStaleWrongWords(int now) async {
    calls.add('decay');
    return 0;
  }

  @override
  Future<int> expireStaleImportBatches(int now) async {
    calls.add('expireBatches');
    return 0;
  }
}

/// 手动触发的假定时器。
class FakeTimer implements MaintenanceTimer {
  new(this.duration, this.onElapsed);

  /// 这一次排期请求的间隔。
  final Duration duration;

  /// 到点时要跑的回调。
  final void Function() onElapsed;

  /// 是否已被 [cancel] 撤销。
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;
}

/// 由用例掌控节奏的排期器：时间不会自己走，要不要「到点」由测试说了算。
class FakeScheduler {
  /// 按创建顺序记录的所有定时器。
  final List<FakeTimer> timers = <FakeTimer>[];

  /// 可直接塞进 [InitializationMaintenance] 的工厂。
  MaintenanceTimer create(Duration duration, void Function() onElapsed) {
    final timer = FakeTimer(duration, onElapsed);
    timers.add(timer);
    return timer;
  }

  /// 最近一次排期的时长。
  Duration get lastDelay => timers.last.duration;

  /// 触发最近一次尚未被取消的定时器，返回它请求的间隔。
  Duration fire() {
    for (final timer in timers.reversed) {
      if (timer.cancelled) continue;
      timer.onElapsed();
      return timer.duration;
    }
    return Duration.zero;
  }
}

void main() {
  const tickInterval = Duration(milliseconds: 20);
  const policy = MaintenancePolicy(tickInterval: tickInterval);
  final now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;

  group('start', () {
    test('按「回收 RUNNING → 回收失败 → 回收历史数据 → 处理一批 → 挂定时器」的顺序执行', () async {
      final runner = RecordingRunner();
      final maintenance = InitializationMaintenance(runner, policy);
      addTearDown(maintenance.dispose);

      expect(maintenance.isRunning, isFalse);
      await maintenance.start(now: now);

      expect(runner.calls, <String>[
        'reset(staleOnly: false)',
        'retryFailed',
        'decay',
        'expireBatches',
        'tick',
      ]);
      expect(maintenance.isRunning, isTrue);
    });

    test('runInitialCleanup 为假时跳过崩溃恢复', () async {
      final runner = RecordingRunner();
      final maintenance = InitializationMaintenance(
        runner,
        const MaintenancePolicy(
          tickInterval: tickInterval,
          runInitialCleanup: false,
        ),
      );
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);

      expect(runner.calls, <String>[
        'retryFailed',
        'decay',
        'expireBatches',
        'tick',
      ]);
    });

    test('runStaleDataCleanup 为假时跳过错词衰减与批次过期', () async {
      final runner = RecordingRunner();
      final maintenance = InitializationMaintenance(
        runner,
        const MaintenancePolicy(
          tickInterval: tickInterval,
          runStaleDataCleanup: false,
        ),
      );
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);

      expect(runner.calls, <String>[
        'reset(staleOnly: false)',
        'retryFailed',
        'tick',
      ]);
    });

    test('历史数据回收失败时仍然会挂上定时器', () async {
      final runner = RecordingRunner()..failWith = FakeFailure('table locked');
      final maintenance = InitializationMaintenance(runner, policy);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);

      expect(maintenance.isRunning, isTrue);
      expect(runner.calls, contains('tick'));
    });

    test('重复调用不会挂第二个定时器', () async {
      final runner = RecordingRunner();
      final maintenance = InitializationMaintenance(runner, policy);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);
      await maintenance.start(now: now);

      expect(runner.calls.where((call) => call == 'tick'), hasLength(1));
    });

    test('回收步骤失败时仍然会挂上定时器', () async {
      final runner = RecordingRunner()..failWith = FakeFailure('db locked');
      final maintenance = InitializationMaintenance(runner, policy);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);

      expect(maintenance.isRunning, isTrue);
      expect(runner.calls, contains('tick'));
    });

    test('定时器到期会再跑一批', () async {
      final runner = RecordingRunner();
      final maintenance = InitializationMaintenance(runner, policy);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);
      await Future<void>.delayed(tickInterval * 3);

      expect(
        runner.calls.where((call) => call == 'tick').length,
        greaterThan(1),
      );
    });
  });

  group('自适应间隔', () {
    const idleInterval = Duration(minutes: 10);
    const busyInterval = Duration(seconds: 20);

    /// 构造一个由假排期器驱动的维护对象。
    InitializationMaintenance build(
      RecordingRunner runner,
      FakeScheduler scheduler,
    ) => InitializationMaintenance(
      runner,
      const MaintenancePolicy(busyTickInterval: busyInterval),
      () => now,
      scheduler.create,
    );

    test('启动批次有产出时直接接着排短间隔', () async {
      final runner = RecordingRunner()..tickResult = 2;
      final scheduler = FakeScheduler();
      final maintenance = build(runner, scheduler);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);

      // 刚导入完词条时最怕的就是「首批跑完后再等 10 分钟」。
      expect(scheduler.lastDelay, busyInterval);
    });

    test('启动批次无事可做时按长间隔保活', () async {
      final runner = RecordingRunner();
      final scheduler = FakeScheduler();
      final maintenance = build(runner, scheduler);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);

      expect(scheduler.lastDelay, idleInterval);
    });

    test('上一批处理了任务时，下一批改用短间隔', () async {
      final runner = RecordingRunner();
      final scheduler = FakeScheduler();
      final maintenance = build(runner, scheduler);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);
      expect(scheduler.lastDelay, idleInterval);

      runner.tickResult = 2;
      expect(scheduler.fire(), idleInterval);
      await pumpEventQueue();

      expect(scheduler.lastDelay, busyInterval);
    });

    test('上一批无事可做时回到长间隔', () async {
      final runner = RecordingRunner();
      final scheduler = FakeScheduler();
      final maintenance = build(runner, scheduler);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);
      runner.tickResult = 2;
      scheduler.fire();
      await pumpEventQueue();
      expect(scheduler.lastDelay, busyInterval);

      runner.tickResult = 0;
      scheduler.fire();
      await pumpEventQueue();

      expect(scheduler.lastDelay, idleInterval);
    });

    test('tick 失败被吞掉，仍按空闲间隔排期', () async {
      final runner = RecordingRunner()..failWith = FakeFailure('db locked');
      final scheduler = FakeScheduler();
      final maintenance = build(runner, scheduler);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);
      scheduler.fire();
      await pumpEventQueue();

      expect(scheduler.lastDelay, idleInterval);
    });

    test('每次只挂一个定时器，排期是替换而不是叠加', () async {
      final runner = RecordingRunner();
      final scheduler = FakeScheduler();
      final maintenance = build(runner, scheduler);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);
      scheduler.fire();
      await pumpEventQueue();

      expect(scheduler.timers, hasLength(2));
      expect(scheduler.timers.first.cancelled, isTrue);
    });
  });

  group('dispose', () {
    test('取消尚未到期的定时器且不再重新排期', () async {
      final runner = RecordingRunner();
      final scheduler = FakeScheduler();
      final maintenance = InitializationMaintenance(
        runner,
        policy,
        () => now,
        scheduler.create,
      );

      await maintenance.start(now: now);
      expect(scheduler.lastDelay, tickInterval);

      maintenance.dispose();

      expect(scheduler.timers.last.cancelled, isTrue);
      expect(maintenance.isRunning, isFalse);
      final before = runner.calls.length;
      expect(scheduler.fire(), Duration.zero);
      await pumpEventQueue();
      expect(runner.calls, hasLength(before));
      expect(scheduler.timers, hasLength(1));
    });

    test('tick 正在跑时 dispose 不会再排期', () async {
      final runner = RecordingRunner();
      final scheduler = FakeScheduler();
      final maintenance = InitializationMaintenance(
        runner,
        policy,
        () => now,
        scheduler.create,
      );

      await maintenance.start(now: now);
      final gate = Completer<void>();
      runner.tickGate = gate;
      scheduler.fire();
      await pumpEventQueue();
      // 上一批还卡在闸门上，不该已经有新的排期。
      expect(scheduler.timers, hasLength(1));
      maintenance.dispose();
      gate.complete();
      await pumpEventQueue();

      expect(maintenance.isRunning, isFalse);
      // 闸门放开后也不重新排期，否则定时器会在 dispose 之后复活。
      expect(scheduler.timers, hasLength(1));
    });

    test('启动途中被 dispose 不会留下定时器', () async {
      final gate = Completer<void>();
      final runner = RecordingRunner()..tickGate = gate;
      final scheduler = FakeScheduler();
      final maintenance = InitializationMaintenance(
        runner,
        policy,
        () => now,
        scheduler.create,
      );

      final starting = maintenance.start(now: now);
      await pumpEventQueue();
      maintenance.dispose();
      gate.complete();
      await starting;

      expect(scheduler.timers, isEmpty);
      expect(maintenance.isRunning, isFalse);
    });

    test('取消定时器', () async {
      final runner = RecordingRunner();
      final maintenance = InitializationMaintenance(runner, policy);

      await maintenance.start(now: now);
      maintenance.dispose();
      final before = runner.calls.length;
      await Future<void>.delayed(tickInterval * 3);

      expect(maintenance.isRunning, isFalse);
      expect(runner.calls, hasLength(before));
    });

    test('释放后可以再次 start', () async {
      final runner = RecordingRunner();
      final maintenance = InitializationMaintenance(runner, policy);

      await maintenance.start(now: now);
      maintenance.dispose();
      await maintenance.start(now: now);

      expect(maintenance.isRunning, isTrue);
      expect(runner.calls.where((call) => call == 'tick'), hasLength(2));
      maintenance.dispose();
    });
  });

  group('pumpOnce', () {
    test('返回执行器给出的处理数量', () async {
      final runner = RecordingRunner()..tickResult = 3;
      final maintenance = InitializationMaintenance(runner, policy);
      addTearDown(maintenance.dispose);

      expect(await maintenance.pumpOnce(now: now), 3);
      expect(runner.calls, <String>['tick']);
    });

    test('不挂定时器', () async {
      final runner = RecordingRunner();
      final maintenance = InitializationMaintenance(runner, policy);
      addTearDown(maintenance.dispose);

      await maintenance.pumpOnce(now: now);

      expect(maintenance.isRunning, isFalse);
    });

    test('失败被吞掉并返回 0', () async {
      final runner = RecordingRunner()..failWith = FakeFailure('boom');
      final maintenance = InitializationMaintenance(runner, policy);
      addTearDown(maintenance.dispose);

      expect(await maintenance.pumpOnce(now: now), 0);
    });

    test('不发后台通知：它是用户主动点的，不是调度器排的那一批', () async {
      final runner = RecordingRunner()..tickResult = 3;
      final maintenance = InitializationMaintenance(runner, policy);
      addTearDown(maintenance.dispose);
      final seen = <int>[];
      maintenance.addTickListener(seen.add);

      await maintenance.pumpOnce(now: now);

      expect(seen, isEmpty);
    });
  });

  group('后台 tick 通知', () {
    test('一批跑完后把处理数量通知给监听者', () async {
      final runner = RecordingRunner()..tickResult = 2;
      final scheduler = FakeScheduler();
      final maintenance = InitializationMaintenance(
        runner,
        policy,
        () => now,
        scheduler.create,
      );
      addTearDown(maintenance.dispose);
      final seen = <int>[];
      maintenance.addTickListener(seen.add);

      await maintenance.start(now: now);
      runner.tickResult = 5;
      scheduler.fire();
      await pumpEventQueue();

      expect(seen, <int>[2, 5]);
    });

    test('tick 失败时不通知界面：没有产出就不该触发刷新', () async {
      final runner = RecordingRunner();
      final scheduler = FakeScheduler();
      final maintenance = InitializationMaintenance(
        runner,
        policy,
        () => now,
        scheduler.create,
      );
      addTearDown(maintenance.dispose);
      final seen = <int>[];
      maintenance.addTickListener(seen.add);

      await maintenance.start(now: now);
      runner.failWith = FakeFailure('db locked');
      scheduler.fire();
      await pumpEventQueue();

      expect(seen, <int>[0]);
    });

    test('取消订阅后不再收到通知', () async {
      final runner = RecordingRunner()..tickResult = 1;
      final scheduler = FakeScheduler();
      final maintenance = InitializationMaintenance(
        runner,
        policy,
        () => now,
        scheduler.create,
      );
      addTearDown(maintenance.dispose);
      final seen = <int>[];
      maintenance
        ..addTickListener(seen.add)
        ..removeTickListener(seen.add);

      await maintenance.start(now: now);
      scheduler.fire();
      await pumpEventQueue();

      expect(seen, isEmpty);
    });

    test('监听者之间互不影响：取消自己不会打断其它监听者', () async {
      final runner = RecordingRunner()..tickResult = 1;
      final scheduler = FakeScheduler();
      final maintenance = InitializationMaintenance(
        runner,
        policy,
        () => now,
        scheduler.create,
      );
      addTearDown(maintenance.dispose);
      final seen = <int>[];
      late MaintenanceTickListener quitter;
      quitter = (processed) {
        seen.add(processed);
        maintenance.removeTickListener(quitter);
      };
      maintenance
        ..addTickListener(quitter)
        ..addTickListener(seen.add);

      await maintenance.start(now: now);

      // 只发生一次通知：quitter 先跑并把自己摘掉，
      // 排在它后面的监听者仍然要收到这一轮。
      expect(seen, <int>[1, 1]);
    });
  });

  group('重入保护', () {
    test('上一批未跑完时 pumpOnce 直接返回 0', () async {
      final gate = Completer<void>();
      final runner = RecordingRunner()..tickGate = gate;
      final maintenance = InitializationMaintenance(runner, policy);
      addTearDown(maintenance.dispose);

      final first = maintenance.pumpOnce(now: now);
      await Future<void>.delayed(Duration.zero);
      final second = await maintenance.pumpOnce(now: now);

      expect(second, 0);
      gate.complete();
      await first;
    });

    test('维护跑动期间的定时器不会并发 tick', () async {
      final runner = RecordingRunner();
      final maintenance = InitializationMaintenance(
        runner,
        const MaintenancePolicy(
          tickInterval: Duration(milliseconds: 5),
          runInitialCleanup: false,
        ),
      );
      addTearDown(maintenance.dispose);

      // 先让启动批次正常跑完（start 会 await 它，装上闸门会死等）。
      await maintenance.start(now: now);
      final gate = Completer<void>();
      runner.tickGate = gate;
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(runner.maxConcurrentTicks, 1);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 15));
    });

    test('跑完之后锁会释放', () async {
      final gate = Completer<void>();
      final runner = RecordingRunner()
        ..tickResult = 1
        ..tickGate = gate;
      final maintenance = InitializationMaintenance(runner, policy);
      addTearDown(maintenance.dispose);

      final first = maintenance.pumpOnce(now: now);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await first;

      expect(await maintenance.pumpOnce(now: now), 1);
    });
  });

  group('kick / pause / resume', () {
    const idleInterval = Duration(minutes: 10);
    const busyInterval = Duration(seconds: 5);

    InitializationMaintenance build(
      RecordingRunner runner,
      FakeScheduler scheduler,
    ) => InitializationMaintenance(
      runner,
      const MaintenancePolicy(),
      () => now,
      scheduler.create,
    );

    test('未 start 时 kick / pause / resume 均为安全空操作', () {
      final runner = RecordingRunner();
      final scheduler = FakeScheduler();
      build(runner, scheduler)
        ..kick()
        ..pause()
        ..resume();

      expect(runner.calls, isEmpty);
      expect(scheduler.timers, isEmpty);
    });

    test('空闲状态下 kick 会立刻取消长定时并立即执行一次 tick', () async {
      final runner = RecordingRunner();
      final scheduler = FakeScheduler();
      final maintenance = build(runner, scheduler);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);
      expect(scheduler.lastDelay, idleInterval);

      runner.tickResult = 2;
      maintenance.kick();
      await pumpEventQueue();

      expect(runner.calls.where((c) => c == 'tick'), hasLength(2));
      expect(scheduler.timers.first.cancelled, isTrue);
      expect(scheduler.lastDelay, busyInterval);
    });

    test('tick 正在跑时 kick 会标记待续跑，完成后按短间隔排期', () async {
      final runner = RecordingRunner();
      final scheduler = FakeScheduler();
      final maintenance = build(runner, scheduler);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);
      final gate = Completer<void>();
      runner
        ..tickResult = 0
        ..tickGate = gate;
      scheduler.fire();
      await pumpEventQueue();

      maintenance.kick();
      gate.complete();
      await pumpEventQueue();

      expect(scheduler.lastDelay, busyInterval);
    });

    test('pause 取消定时器并阻塞触发，resume 回到前台立即恢复', () async {
      final runner = RecordingRunner();
      final scheduler = FakeScheduler();
      final maintenance = build(runner, scheduler);
      addTearDown(maintenance.dispose);

      await maintenance.start(now: now);
      maintenance.pause();
      expect(maintenance.isPaused, isTrue);
      expect(scheduler.timers.last.cancelled, isTrue);

      maintenance.kick();
      await pumpEventQueue();
      expect(runner.calls.where((c) => c == 'tick'), hasLength(1));

      maintenance.resume();
      await pumpEventQueue();
      expect(maintenance.isPaused, isFalse);
      expect(runner.calls.where((c) => c == 'tick'), hasLength(2));
      expect(scheduler.timers.last.cancelled, isFalse);
    });
  });
}
