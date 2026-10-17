/// 自动备份：按周期检查，数据确实变了才上传。
///
/// **为什么不是 `Timer.periodic`**：真实周期可能是「每 7 天」，但配置随时可改、
/// 数据也随时在变。用一个固定的检查节奏（[webdavAutoCheckIntervalMs]）醒来，
/// 每次醒来重新判断「周期到了没有、数据变了没有」，比挂一个长定时器更好——
/// 后者在用户改完设置后仍按旧周期等待，且应用重启才会生效。
///
/// **为什么自动备份失败只写状态**：它是后台行为，用户没在等它。弹 SnackBar
/// 会在用户正在答题时插一条「上传失败」，而真正的处置时机是用户下次进设置页。
/// 失败原因写进设置行，设置页与状态行读它。
///
/// **与界面的关系**：本类从不被界面 `watch`，只由
/// `lib/app/maintenance_bootstrap.dart` 点火一次，随 `ProviderScope` 释放。
library;

import 'dart:async';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/backup_checkpoint_dao.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';
import 'package:lexiloop/services/remote_backup/webdav_state_store.dart';
import 'package:lexiloop/services/remote_backup/webdav_upload_service.dart';
import 'package:lexiloop/services/scheduling/one_shot_timer.dart';

/// 下一次检查该等多久。
///
/// **写成纯函数**：调度规则（周期没到就睡到差不多到期时再看、已经到期就按
/// 固定节奏复查）是这块逻辑里最容易算错、也最难在真机上复现的部分，
/// 抽出来之后可以脱离定时器逐条断言。
Duration webdavNextCheckDelay({
  required WebdavBackupState state,
  required int now,
}) {
  const checkInterval = Duration(milliseconds: webdavAutoCheckIntervalMs);
  if (!state.autoEnabled) return checkInterval;
  final lastSuccessAt = state.lastSuccessAt;
  // 从未成功过 ⇒ 已经到期（但下面仍然只按检查节奏复查，
  // 避免失败后每 5 分钟就重试一次完整上传）。
  if (lastSuccessAt == null) return checkInterval;
  final dueAt = lastSuccessAt + state.autoInterval.inMilliseconds;
  final remaining = dueAt - now;
  if (remaining <= 0) return checkInterval;
  return remaining < webdavAutoCheckIntervalMs
      ? Duration(milliseconds: remaining)
      : checkInterval;
}

/// 自动备份的调度器。
class WebdavAutoBackup {
  /// 以上传服务、检查点 DAO 与状态存储构造。
  ///
  /// `clock` 与 `timerFactory` 是可测性接缝：默认读系统时钟、挂真实 `Timer`；
  /// 测试传入假时钟与假定时器后，整条排期链路不需要等待墙钟。
  new(
    this._uploader,
    this._checkpoints,
    this._states, [
    int Function()? clock,
    MaintenanceTimerFactory? timerFactory,
  ]) : _clock = clock ?? _wallClockMs,
       _timerFactory = timerFactory ?? createRealMaintenanceTimer;

  final WebdavUploadService _uploader;
  final BackupCheckpointDao _checkpoints;
  final WebdavStateStore _states;
  final int Function() _clock;
  final MaintenanceTimerFactory _timerFactory;

  MaintenanceTimer? _timer;
  bool _running = false;
  bool _checking = false;

  /// 是否已启动且尚未 [dispose]。
  bool get isRunning => _running;

  /// 立即评估一次并挂上下一次检查。
  ///
  /// 可重复调用；第二次直接返回，不会挂第二个定时器。
  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _check();
    if (!_running) return;
    await _schedule();
  }

  /// 取消挂起的检查；之后 [start] 可以重新点火。
  void dispose() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 按当前状态排下一次检查。
  Future<void> _schedule() async {
    final delay = await _delay();
    if (!_running) return;
    _timer?.cancel();
    _timer = _timerFactory(delay, () => unawaited(_tick()));
  }

  /// 定时器到点：评估一次再排下一次。
  Future<void> _tick() async {
    if (!_running) return;
    await _check();
    if (!_running) return;
    await _schedule();
  }

  /// 一次检查：未启用则什么都不做；到期且检查点变了才上传。
  Future<void> _check() async {
    // 重入保护：上一轮上传还没结束时不再叠一轮（27MB 上传可能超过检查间隔）。
    if (_checking) return;
    _checking = true;
    try {
      final state = (await _states.load()).state;
      if (_isDue(state) && await _hasChanged(state)) await _upload();
    } on Object {
      // 后台行为，任何异常都在各自的分支里落过状态；这里只保证调度不中断。
    } finally {
      _checking = false;
    }
  }

  /// 周期是否已到（从未成功过视为到期）。
  bool _isDue(WebdavBackupState state) {
    if (!state.autoEnabled) return false;
    final lastSuccessAt = state.lastSuccessAt;
    if (lastSuccessAt == null) return true;
    return _clock() - lastSuccessAt >= state.autoInterval.inMilliseconds;
  }

  /// 数据相对上次成功上传是否发生了变化。
  ///
  /// 第一次上传（没有历史检查点）永远算「变了」——否则用户配好自动备份后
  /// 要等到第一次数据变动才会有第一份远端备份。
  Future<bool> _hasChanged(WebdavBackupState state) async {
    final saved = state.lastCheckpoint;
    if (saved == null) return true;
    return checkpointWire(await _checkpoints.current()) != saved;
  }

  /// 上传一次；失败只写状态，不上抛。
  Future<void> _upload() async {
    try {
      await _uploader.uploadNow();
    } on AppError catch (error) {
      await _states.recordFailure(error.code.code);
    }
  }

  /// 下一次检查的延迟，按**当前读到的**状态计算。
  Future<Duration> _delay() async {
    final state = (await _states.load()).state;
    return webdavNextCheckDelay(state: state, now: _clock());
  }
}

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;
