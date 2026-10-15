/// 学习答题的活跃计时器。
///
/// 对应旧版 `src/lib/use-active-stopwatch.ts`。旧版本版只在收尾时给时长夹一个
/// 上界（见 `domain/review/duration.dart` 的 `boundedActiveDurationMs`），
/// 那无法区分「思考了 3 分钟」和「挂机 3 分钟再回来敲一个字」——后者整段都会
/// 被算成活跃。本类的做法是**真的把计时停掉**：空闲 `idleTimeoutMs` 毫秒后由
/// 定时器关闭当前活跃段，之后的交互只能从那一刻重新开始累计。
///
/// 本文件不依赖 Flutter：生命周期与输入事件由 `study_page.dart` 转成
/// `setVisible` / `touch`，计时规则因此可以脱离 widget 树单测。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:lexiloop/core/constants.dart';

int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

/// 只统计前台交互时间的秒表。
class StudyClock {
  /// 以可注入的时钟与空闲阈值构造。
  ///
  /// [now] 默认取系统时间；测试必须注入与假定时器同步的时钟，否则
  /// `Timer` 走假时间、`DateTime.now()` 走真实时间，「45 秒空闲」这条规则
  /// 在测试里根本构造不出来。
  new({int Function()? now, this.idleTimeoutMs = activeIdleTimeoutMs})
    : _now = now ?? _systemNowMs;

  /// 多久没有交互就判定为空闲（毫秒）。
  final int idleTimeoutMs;

  final int Function() _now;

  int _accumulatedMs = 0;
  int? _activeSince;
  int _lastActivityAt = 0;
  Timer? _idleTimer;
  bool _enabled = false;
  bool _visible = true;

  /// 累计的活跃毫秒数（含当前尚未关闭的活跃段）。
  int elapsedMs() {
    final activeSince = _activeSince;
    if (activeSince == null) return _accumulatedMs;
    return _accumulatedMs + _segmentEnd(activeSince) - activeSince;
  }

  /// 设置「是否答题中且未揭示答案」；关闭时立刻停止计时。
  void setEnabled({required bool enabled}) {
    _enabled = enabled;
    if (enabled) {
      resume();
    } else {
      pause();
    }
  }

  /// 设置「页面可见且窗口聚焦」；不可见时立刻停止计时。
  ///
  /// 与 [pause] 分开：`pause` 只停当前段，恢复与否由这个开关决定，
  /// 否则失焦期间来一次交互就会把计时又续上。
  void setVisible({required bool visible}) {
    _visible = visible;
    if (visible) {
      resume();
    } else {
      pause();
    }
  }

  /// 记录一次用户交互：续上活跃段并重新排空闲暂停。
  void touch() => resume();

  /// 开始（或续上）活跃段。
  ///
  /// 不可见或不在答题状态时什么也不做——这正是旧版 `resume()` 里
  /// `document.visibilityState !== "visible" || !document.hasFocus()` 那两行。
  void resume() {
    if (!_enabled || !_visible) return;
    final now = _now();
    _lastActivityAt = now;
    _activeSince ??= now;
    _scheduleIdlePause();
  }

  /// 停止活跃段；累计值不变。
  void pause() => _stopSegment();

  /// 换题时清零并重新开始计时。
  ///
  /// 旧版是 `reset()` 后立刻 `resume()`：新题的计时从换题那一刻起算，
  /// 而不是等用户第一次交互。
  void reset() {
    _accumulatedMs = 0;
    _activeSince = null;
    _lastActivityAt = 0;
    _cancelIdleTimer();
    resume();
  }

  /// 结算：停止计时并返回累计毫秒。
  int capture() {
    _stopSegment();
    return _accumulatedMs;
  }

  /// 释放空闲定时器。
  ///
  /// 不调用会让挂起的 `Timer` 在 widget 测试结束时被判为「测试后仍有定时器」。
  void dispose() => _cancelIdleTimer();

  /// 当前活跃段的结束时刻。
  ///
  /// `min(now, lastActivityAt + idleTimeoutMs)` 是空闲上界，`max(activeSince, …)`
  /// 兜住时钟回拨——回拨时 `now` 可能早于 `activeSince`，不减成负数。
  int _segmentEnd(int activeSince) {
    final now = _now();
    final cutoff = _lastActivityAt > 0 ? _lastActivityAt + idleTimeoutMs : now;
    return math.max(activeSince, math.min(now, cutoff));
  }

  void _stopSegment() {
    final activeSince = _activeSince;
    if (activeSince == null) return;
    _accumulatedMs += _segmentEnd(activeSince) - activeSince;
    _activeSince = null;
    _cancelIdleTimer();
  }

  void _scheduleIdlePause() {
    _cancelIdleTimer();
    final remaining = _lastActivityAt + idleTimeoutMs - _now();
    _idleTimer = Timer(
      Duration(milliseconds: remaining < 0 ? 0 : remaining),
      _stopSegment,
    );
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }
}
