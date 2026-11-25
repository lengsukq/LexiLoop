/// 「双端词环共振桥」自绘层（纯 `CustomPainter`，零三方动画依赖）。
///
/// 视觉隐喻直接来自 LexiLoop「词环」：
/// - 左右双设备外圈各有一条精密确定性进度环（主色发送、次色接收，带端点高光点）；
/// - 中央两条柔和分离的三次贝塞尔流光轨从双环 ±16° 切线自然舒展，
///   消除尖锐夹角：上轨「本机 → 对端」（主色彗尾），下轨「对端 → 本机」（次色彗尾）；
/// - 严格响应当前主题 `LexiColors` 与系统「减弱动态效果」。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';

/// 节点外圈进度环半径（相对设备胶囊中心）。
const double syncNodeRingRadius = 29;

/// 双弧相对中轴的优雅拱起高度。
const double _arcLift = 20;

/// 双弧端点相对中轴的上下分离偏移（避免在圆环处捏成尖角）。
const double _railAnchorOffsetY = 8;

/// 弧线起点距离进度环边缘的光学留隙。
const double _railRingGap = 7;

/// 基础轨道线宽。
const double _railStrokeWidth = 1.6;

/// 进度环与活动光弧线宽。
const double _ringStrokeWidth = 2.8;

/// 彗尾核心线宽。
const double _cometCoreWidth = 2.6;

/// 彗尾柔和外光晕线宽。
const double _cometGlowWidth = 7;

/// 彗头高亮圆半径。
const double _cometHeadRadius = 3;

/// 单枚彗尾占弧长比例。
const double _cometTrailSpan = 0.28;

/// 传输态每条活动轨道的并发光粒数。
const int _activeCometCount = 2;

/// 中央合并双轨环半径。
const double _mergeOrbitRadius = 22;

/// 动效相位打包参数，避免画笔构造函数形参膨胀。
@immutable
class LanSyncBridgeMotion {
  /// 以流光相位、光晕相位与减弱动态开关构造。
  const new({
    required this.flowPhase,
    required this.bloomPhase,
    required this.reducedMotion,
  });

  /// 连续流光相位（`0.0`–`1.0`）。
  final double flowPhase;

  /// 一次性光晕绽放相位（`0.0`–`1.0`）。
  final double bloomPhase;

  /// 是否启用了系统「减弱动态效果」。
  final bool reducedMotion;

  @override
  bool operator ==(Object other) =>
      other is LanSyncBridgeMotion &&
      other.flowPhase == flowPhase &&
      other.bloomPhase == bloomPhase &&
      other.reducedMotion == reducedMotion;

  @override
  int get hashCode => Object.hash(flowPhase, bloomPhase, reducedMotion);
}

/// 「双端词环共振桥」画笔。
class LanSyncBridgePainter extends CustomPainter {
  /// 以进度、主题色、节点水平内缩与动效参数构造。
  const new({
    required this.progress,
    required this.colors,
    required this.nodeInset,
    required this.motion,
  });

  /// 当前同步进度快照。
  final LanSyncTransferProgress progress;

  /// 当前主题语义色板。
  final LexiColors colors;

  /// 左右设备中心到舞台边缘的水平距离（与舞台定位完全共用，确保同心对齐）。
  final double nodeInset;

  /// 动效相位与减弱动态配置。
  final LanSyncBridgeMotion motion;

  double get _flow => motion.flowPhase;

  double get _bloom => motion.bloomPhase;

  bool get _reduced => motion.reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= nodeInset * 2 + syncNodeRingRadius) return;
    final cy = size.height / 2;
    final left = Offset(nodeInset, cy);
    final right = Offset(size.width - nodeInset, cy);
    final center = Offset(size.width / 2, cy);

    _drawBaseRails(canvas, left, right);
    _drawPhaseVisuals(canvas, left, right, center);
    _drawNodeRing(
      canvas,
      center: left,
      color: _leftRingColor(),
      fraction: _leftRingFraction(),
      indeterminate: _isIndeterminate && _hasUploadTrack,
    );
    _drawNodeRing(
      canvas,
      center: right,
      color: _rightRingColor(),
      fraction: _rightRingFraction(),
      indeterminate: _isIndeterminate && _hasDownloadTrack,
      dashed: progress.peer == null,
    );
  }

  bool get _hasUploadTrack => progress.direction != LanSyncDirection.pullOnly;

  bool get _hasDownloadTrack => progress.direction != LanSyncDirection.pushOnly;

  bool get _isIndeterminate =>
      !_reduced &&
      (progress.phase == LanSyncPhase.connecting ||
          progress.phase == LanSyncPhase.diffing ||
          progress.phase == LanSyncPhase.merging);

  ({Offset upStart, Offset upEnd, Offset downStart, Offset downEnd}) _anchors(
    Offset left,
    Offset right,
  ) {
    final sx = left.dx + syncNodeRingRadius + _railRingGap;
    final ex = right.dx - syncNodeRingRadius - _railRingGap;
    return (
      upStart: Offset(sx, left.dy - _railAnchorOffsetY),
      upEnd: Offset(ex, right.dy - _railAnchorOffsetY),
      downStart: Offset(sx, left.dy + _railAnchorOffsetY),
      downEnd: Offset(ex, right.dy + _railAnchorOffsetY),
    );
  }

  Color _leftRingColor() => switch (progress.phase) {
    LanSyncPhase.completed => colors.success,
    LanSyncPhase.failed => colors.danger,
    _ => colors.accent,
  };

  Color _rightRingColor() => switch (progress.phase) {
    LanSyncPhase.completed => colors.success,
    LanSyncPhase.failed => colors.danger,
    _ => progress.peer == null ? colors.borderDefault : colors.secondary,
  };

  double _leftRingFraction() {
    if (progress.phase == LanSyncPhase.completed) return 1;
    if (progress.phase == LanSyncPhase.failed) return 0;
    if (progress.phase != LanSyncPhase.transferring) return 0;
    final m = progress.detail.bytes;
    return _hasUploadTrack ? m.uploadProgress : m.downloadProgress;
  }

  double _rightRingFraction() {
    if (progress.peer == null || progress.phase == LanSyncPhase.failed) {
      return 0;
    }
    if (progress.phase == LanSyncPhase.completed) return 1;
    if (progress.phase != LanSyncPhase.transferring) return 0;
    final m = progress.detail.bytes;
    return _hasDownloadTrack ? m.downloadProgress : m.uploadProgress;
  }

  void _drawBaseRails(Canvas canvas, Offset left, Offset right) {
    final a = _anchors(left, right);
    if (a.upEnd.dx <= a.upStart.dx) return;

    if (progress.phase == LanSyncPhase.waiting ||
        progress.phase == LanSyncPhase.failed) {
      final base = progress.phase == LanSyncPhase.failed
          ? colors.danger.withValues(alpha: LexiTint.border)
          : colors.borderStrong.withValues(alpha: LexiTint.half);
      final paint = Paint()
        ..color = base
        ..style = PaintingStyle.stroke
        ..strokeWidth = _railStrokeWidth
        ..strokeCap = StrokeCap.round;
      _drawDashedArc(canvas, a.upStart, a.upEnd, -_arcLift, paint);
      _drawDashedArc(canvas, a.downStart, a.downEnd, _arcLift, paint);
      return;
    }
    _drawFadedRail(
      canvas,
      a.upStart,
      a.upEnd,
      -_arcLift,
      color: _hasUploadTrack ? colors.accent : colors.borderDefault,
      peakAlpha: _hasUploadTrack ? LexiTint.border : LexiTint.tint,
    );
    _drawFadedRail(
      canvas,
      a.downStart,
      a.downEnd,
      _arcLift,
      color: _hasDownloadTrack ? colors.secondary : colors.borderDefault,
      peakAlpha: _hasDownloadTrack ? LexiTint.border : LexiTint.tint,
    );
  }

  void _drawFadedRail(
    Canvas canvas,
    Offset start,
    Offset end,
    double lift, {
    required Color color,
    required double peakAlpha,
  }) {
    final shader = LinearGradient(
      colors: <Color>[
        color.withValues(alpha: LexiTint.subtle),
        color.withValues(alpha: peakAlpha),
        color.withValues(alpha: LexiTint.subtle),
      ],
    ).createShader(Rect.fromPoints(start, end));
    canvas.drawPath(
      _arcPath(start, end, lift),
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = _railStrokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawPhaseVisuals(
    Canvas canvas,
    Offset left,
    Offset right,
    Offset center,
  ) {
    final a = _anchors(left, right);
    if (a.upEnd.dx <= a.upStart.dx) return;

    switch (progress.phase) {
      case LanSyncPhase.waiting:
        if (!_reduced && _bloom > 0 && _bloom < 1) {
          _drawRadarRipples(canvas, left);
        }
      case LanSyncPhase.connecting || LanSyncPhase.diffing:
        if (!_reduced) {
          _drawCometStream(
            canvas,
            start: a.upStart,
            end: a.upEnd,
            lift: -_arcLift,
            color: colors.accent,
            count: 1,
          );
          _drawCometStream(
            canvas,
            start: a.downEnd,
            end: a.downStart,
            lift: _arcLift,
            color: colors.secondary,
            count: 1,
          );
        }
      case LanSyncPhase.transferring:
        if (!_reduced) _drawTransferComets(canvas, a);
      case LanSyncPhase.merging:
        if (!_reduced) _drawMergeOrbit(canvas, center);
      case LanSyncPhase.completed:
        _drawConvergedBridge(canvas, a, center);
      case LanSyncPhase.idle || LanSyncPhase.discovering || LanSyncPhase.failed:
        break;
    }
  }

  void _drawTransferComets(
    Canvas canvas,
    ({Offset upStart, Offset upEnd, Offset downStart, Offset downEnd}) a,
  ) {
    if (_hasUploadTrack) {
      _drawCometStream(
        canvas,
        start: a.upStart,
        end: a.upEnd,
        lift: -_arcLift,
        color: colors.accent,
        count: _activeCometCount,
      );
    }
    if (_hasDownloadTrack) {
      _drawCometStream(
        canvas,
        start: a.downEnd,
        end: a.downStart,
        lift: _arcLift,
        color: colors.secondary,
        count: _activeCometCount,
      );
    }
  }

  void _drawRadarRipples(Canvas canvas, Offset origin) {
    for (var wave = 0; wave < 2; wave += 1) {
      final t = (_bloom * 1.35 - wave * 0.30).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) continue;
      final alpha = (1 - t) * LexiTint.border;
      canvas.drawCircle(
        origin,
        syncNodeRingRadius + t * 22,
        Paint()
          ..color = colors.accent.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _railStrokeWidth,
      );
    }
  }

  void _drawCometStream(
    Canvas canvas, {
    required Offset start,
    required Offset end,
    required double lift,
    required Color color,
    required int count,
  }) {
    final path = _arcPath(start, end, lift);
    final metrics = path.computeMetrics().toList(growable: false);
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final total = metric.length;

    for (var i = 0; i < count; i += 1) {
      final head = (_flow + i / count) % 1.0;
      final tail = (head - _cometTrailSpan).clamp(0.0, 1.0);
      if (head <= tail) continue;
      final seg = metric.extractPath(total * tail, total * head);
      final tailPt = metric.getTangentForOffset(total * tail)?.position;
      final headPt = metric.getTangentForOffset(total * head)?.position;
      if (tailPt == null || headPt == null) continue;
      _paintComet(canvas, seg, tailPt, headPt, color);
    }
  }

  void _paintComet(
    Canvas canvas,
    Path segment,
    Offset tail,
    Offset head,
    Color color,
  ) {
    final glowShader = LinearGradient(
      colors: <Color>[
        color.withValues(alpha: LexiTint.none),
        color.withValues(alpha: LexiTint.tint),
      ],
    ).createShader(Rect.fromPoints(tail, head));
    final coreShader = LinearGradient(
      colors: <Color>[
        color.withValues(alpha: LexiTint.none),
        color.withValues(alpha: LexiTint.strong),
      ],
    ).createShader(Rect.fromPoints(tail, head));

    canvas
      ..drawPath(
        segment,
        Paint()
          ..shader = glowShader
          ..style = PaintingStyle.stroke
          ..strokeWidth = _cometGlowWidth
          ..strokeCap = StrokeCap.round,
      )
      ..drawPath(
        segment,
        Paint()
          ..shader = coreShader
          ..style = PaintingStyle.stroke
          ..strokeWidth = _cometCoreWidth
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(
        head,
        _cometHeadRadius * 2.2,
        Paint()..color = color.withValues(alpha: LexiTint.tint),
      )
      ..drawCircle(head, _cometHeadRadius, Paint()..color = color)
      ..drawCircle(
        head,
        _cometHeadRadius * 0.45,
        Paint()..color = Colors.white.withValues(alpha: LexiTint.strong),
      );
  }

  void _drawMergeOrbit(Canvas canvas, Offset center) {
    final angle = _flow * math.pi * 2;
    final rect = Rect.fromCircle(center: center, radius: _mergeOrbitRadius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringStrokeWidth
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawArc(
        rect,
        angle,
        math.pi * 0.65,
        false,
        paint..color = colors.accent,
      )
      ..drawArc(
        rect,
        angle + math.pi,
        math.pi * 0.65,
        false,
        paint..color = colors.secondary,
      );
  }

  void _drawConvergedBridge(
    Canvas canvas,
    ({Offset upStart, Offset upEnd, Offset downStart, Offset downEnd}) a,
    Offset center,
  ) {
    final shader = LinearGradient(
      colors: <Color>[colors.accent, colors.success, colors.secondary],
    ).createShader(Rect.fromPoints(a.upStart, a.downEnd));
    final paint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = _railStrokeWidth
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawPath(_arcPath(a.upStart, a.upEnd, -_arcLift), paint)
      ..drawPath(_arcPath(a.downStart, a.downEnd, _arcLift), paint);

    if (!_reduced && _bloom > 0 && _bloom < 1) {
      final alpha = (1 - _bloom) * LexiTint.border;
      canvas.drawCircle(
        center,
        18 + _bloom * 28,
        Paint()
          ..color = colors.success.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ringStrokeWidth,
      );
    }
  }

  void _drawNodeRing(
    Canvas canvas, {
    required Offset center,
    required Color color,
    required double fraction,
    required bool indeterminate,
    bool dashed = false,
  }) {
    final trackPaint = Paint()
      ..color = colors.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringStrokeWidth;
    if (dashed) {
      _drawDashedCircle(canvas, center, syncNodeRingRadius, trackPaint);
      return;
    }
    canvas.drawCircle(center, syncNodeRingRadius, trackPaint);

    final activePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringStrokeWidth
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: syncNodeRingRadius);
    if (indeterminate) {
      final start = _flow * math.pi * 2 - math.pi / 2;
      canvas.drawArc(rect, start, math.pi * 0.78, false, activePaint);
      return;
    }
    if (fraction > 0) {
      final clamped = fraction.clamp(0.0, 1.0);
      final sweep = math.pi * 2 * clamped;
      canvas.drawArc(rect, -math.pi / 2, sweep, false, activePaint);
      if (clamped < 1) {
        final tipAngle = -math.pi / 2 + sweep;
        final tip = Offset(
          center.dx + syncNodeRingRadius * math.cos(tipAngle),
          center.dy + syncNodeRingRadius * math.sin(tipAngle),
        );
        canvas.drawCircle(
          tip,
          _cometHeadRadius * 1.6,
          Paint()..color = color.withValues(alpha: LexiTint.tint),
        );
      }
    }
  }

  Path _arcPath(Offset start, Offset end, double lift) {
    final span = end.dx - start.dx;
    return Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        start.dx + span * 0.28,
        start.dy + lift,
        start.dx + span * 0.72,
        end.dy + lift,
        end.dx,
        end.dy,
      );
  }

  void _drawDashedArc(
    Canvas canvas,
    Offset start,
    Offset end,
    double lift,
    Paint paint,
  ) {
    final path = _arcPath(start, end, lift);
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        final stop = (d + 4.5).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, stop), paint);
      }
    }
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    const dashes = 18;
    const step = (math.pi * 2) / dashes;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < dashes; i += 1) {
      canvas.drawArc(rect, i * step, step * 0.45, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LanSyncBridgePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.colors != colors ||
      oldDelegate.nodeInset != nodeInset ||
      oldDelegate.motion != motion;
}
