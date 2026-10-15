/// 按真实时间推进游戏时钟的计时器。
///
/// 小游戏、配对、音标三个控制器都需要「每 100ms 把真实经过的毫秒数喂给
/// 状态机」。用 [Stopwatch] 而不是固定步长，是为了让应用卡顿或后台挂起时
/// 倒计时仍然准确——旧版 `use-game-countdown` 用 `deadline - Date.now()`
/// 也是这个理由。抽成一个类，三个控制器不必各写一份。
library;

import 'dart:async';

import 'package:lexiloop/features/games/games_providers.dart';

/// 游戏时钟。
class GameTicker {
  /// 以每次 tick 的回调构造。
  new(this.onTick);

  /// 每次 tick 的回调（可替换，便于控制器在构造后绑定）。
  void Function(int deltaMs) onTick;
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();
  int _lastMs = 0;

  /// 是否正在运行。
  bool get isRunning => _timer != null;

  /// 启动（重复调用会先停止再重新计时）。
  void start() {
    stop();
    _stopwatch
      ..reset()
      ..start();
    _lastMs = 0;
    _timer = Timer.periodic(
      const Duration(milliseconds: gameTickMs),
      (_) => _tick(),
    );
  }

  /// 停止。
  void stop() {
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
  }

  void _tick() {
    final elapsed = _stopwatch.elapsedMilliseconds;
    final delta = elapsed - _lastMs;
    _lastMs = elapsed;
    if (delta <= 0) return;
    onTick(delta);
  }
}
