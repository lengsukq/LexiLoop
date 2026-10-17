/// 可注入、可取消的一次性延迟定时器。
///
/// **为什么要有这层抽象**：真实实现是可取消的 `Timer`，`dispose()` 靠它收回
/// 挂起的回调；测试实现由用例手动触发，于是「什么时候该排下一次」这类调度
/// 规则不需要真的等待墙钟就能断言。守卫还要求 `dispose` 之后不留任何挂起
/// 定时器（否则 `testWidgets` 结尾会报「A Timer is still pending」），
/// 而把 `Future.delayed` 当作延迟原语是拿不到句柄、取消不掉的。
///
/// **为什么放在独立文件**：初始化队列的维护与远程备份的自动上传都需要它。
/// 留在 `initialization_maintenance.dart` 里会让远程备份反向依赖初始化队列
/// ——两个毫不相干的子系统不该因为共用一个 20 行的接缝而连起来。
library;

import 'dart:async';

/// 一次性的延迟定时器。
abstract interface class MaintenanceTimer {
  /// 取消尚未到期的回调；已触发的实现应什么都不做。
  void cancel();
}

/// 创建 [duration] 后回调 [onElapsed] 的一次性定时器。
typedef MaintenanceTimerFactory = MaintenanceTimer Function(
  Duration duration,
  void Function() onElapsed,
);

/// 真实定时器：[Timer] 的薄适配层，只为满足 [MaintenanceTimer]。
class RealMaintenanceTimer implements MaintenanceTimer {
  /// 以延迟与回调构造。
  new(Duration duration, void Function() onElapsed)
    : _timer = Timer(duration, onElapsed);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

/// 生产环境使用的定时器工厂。
MaintenanceTimer createRealMaintenanceTimer(
  Duration duration,
  void Function() onElapsed,
) => RealMaintenanceTimer(duration, onElapsed);
