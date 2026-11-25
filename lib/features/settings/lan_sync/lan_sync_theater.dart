/// 双端同步「词环共振桥」互动动画面板。
///
/// 主机端与拉取端共用本组件，实时呈现：
/// - 响应宽度自适应的全宽双设备共振舞台（设备徽章、同心精密进度环、双轨流光桥）；
/// - 阶段文案与克制的确定性进度条（含压缩节省遥测胶囊）；
/// - 同步完成后的双侧战果卡片；
/// - 严格遵循 `MediaQuery.disableAnimationsOf`，完成/失败/等待态无常驻耗电动画。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/features/settings/backup_size_label.dart';
import 'package:lexiloop/features/settings/lan_sync/lan_sync_theater_painter.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_haptics.dart';
import 'package:lexiloop/ui/theme/lexi_motion.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/lexi_progress_bar.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 共振桥绘制舞台高度（固定尺寸，非间距）。
const double _bridgeStageHeight = 96;

/// 设备圆形内胆直径（同心嵌套于 `syncNodeRingRadius * 2` 进度环内）。
const double _nodePodSize = 46;

/// 中央枢纽徽标直径。
const double _nexusSize = 32;

/// 宽舞台下设备中心距离边缘的水平内缩。
const double _wideNodeInset = 56;

/// 窄舞台（手机竖屏）下设备中心距离边缘的水平内缩。
const double _compactNodeInset = 38;

/// 舞台切换宽/窄内缩的宽度阈值。
const double _wideStageThreshold = 360;

/// 卡片内次级操作按钮的紧凑高度。
const double _compactActionHeight = 36;

/// 双端同步动画面板。
class LanSyncTheater extends StatefulWidget {
  /// 以同步进度快照与可选操作回调构造。
  const new({
    required this.progress,
    this.onCancel,
    this.onDismiss,
    this.onRetry,
    super.key,
  });

  /// 当前同步进度快照。
  final LanSyncTransferProgress progress;

  /// 传输中点击取消时的回调。
  final VoidCallback? onCancel;

  /// 完成或失败后收起面板的回调。
  final VoidCallback? onDismiss;

  /// 失败后重试的回调。
  final VoidCallback? onRetry;

  @override
  State<LanSyncTheater> createState() => _LanSyncTheaterState();
}

class _LanSyncTheaterState extends State<LanSyncTheater>
    with TickerProviderStateMixin {
  late final AnimationController _flow;
  late final AnimationController _bloom;

  @override
  void initState() {
    super.initState();
    _flow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _bloom = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncControllers(previousPhase: null);
  }

  @override
  void didUpdateWidget(covariant LanSyncTheater oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress.phase != widget.progress.phase) {
      _syncControllers(previousPhase: oldWidget.progress.phase);
    }
  }

  void _syncControllers({required LanSyncPhase? previousPhase}) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final phase = widget.progress.phase;
    if (reduced) {
      _flow.stop();
      _bloom.stop();
      return;
    }
    if (widget.progress.isActive) {
      if (!_flow.isAnimating) _flow.repeat();
      if (previousPhase == LanSyncPhase.waiting ||
          previousPhase == LanSyncPhase.idle) {
        LexiHaptics.light();
      }
      return;
    }
    _flow.stop();
    if (phase == LanSyncPhase.completed &&
        previousPhase != LanSyncPhase.completed) {
      LexiHaptics.medium();
      _bloom.forward(from: 0);
    } else if (phase == LanSyncPhase.waiting && previousPhase == null) {
      _bloom.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    _bloom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final progress = widget.progress;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Container(
      key: const Key('lanSyncTheater'),
      padding: const EdgeInsets.all(LexiSpace.s16),
      decoration: _stageDecoration(colors, progress),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TheaterHeader(progress: progress),
          const SizedBox(height: LexiSpace.s12),
          _BridgeStage(
            progress: progress,
            flow: _flow,
            bloom: _bloom,
            reducedMotion: reduced,
          ),
          const SizedBox(height: LexiSpace.s10),
          _StageStatusStrip(progress: progress),
          if (progress.phase == LanSyncPhase.completed) ...<Widget>[
            const SizedBox(height: LexiSpace.s10),
            _CompletedSummaryStrip(progress: progress),
          ],
          if (_hasActions(progress)) ...<Widget>[
            const SizedBox(height: LexiSpace.s8),
            _TheaterActions(
              progress: progress,
              onCancel: widget.onCancel,
              onDismiss: widget.onDismiss,
              onRetry: widget.onRetry,
            ),
          ],
        ],
      ),
    );
  }

  BoxDecoration _stageDecoration(
    LexiColors colors,
    LanSyncTransferProgress progress,
  ) {
    final (Color bg, Color border) = switch (progress.phase) {
      LanSyncPhase.failed => (
        Color.alphaBlend(
          colors.danger.withValues(alpha: LexiTint.group),
          colors.card,
        ),
        colors.danger.withValues(alpha: LexiTint.border),
      ),
      LanSyncPhase.completed => (
        Color.alphaBlend(
          colors.success.withValues(alpha: LexiTint.group),
          colors.card,
        ),
        colors.success.withValues(alpha: LexiTint.border),
      ),
      LanSyncPhase.transferring ||
      LanSyncPhase.merging ||
      LanSyncPhase.connecting ||
      LanSyncPhase.diffing => (
        Color.alphaBlend(
          colors.accent.withValues(alpha: LexiTint.group),
          colors.card,
        ),
        colors.accent.withValues(alpha: LexiTint.border),
      ),
      _ => (colors.card, colors.borderDefault),
    };
    return BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      border: Border.all(color: border),
    );
  }

  bool _hasActions(LanSyncTransferProgress progress) =>
      (progress.isActive && widget.onCancel != null) ||
      (progress.isTerminal &&
          (widget.onDismiss != null || widget.onRetry != null));
}

class _TheaterHeader extends StatelessWidget {
  const new({required this.progress});

  final LanSyncTransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final telemetry = _telemetryLabel(progress);
    return Row(
      children: <Widget>[
        LexiBadge(
          key: const Key('lanSyncTheaterModeBadge'),
          label: _modeBadgeLabel(progress),
          tone: _modeBadgeTone(progress),
        ),
        const Spacer(),
        if (telemetry != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s8,
              vertical: LexiSpace.s2,
            ),
            decoration: BoxDecoration(
              color: colors.fill,
              borderRadius: BorderRadius.circular(LexiRadius.pill),
            ),
            child: Text(
              telemetry,
              key: const Key('lanSyncTheaterTelemetry'),
              style: LexiType.caption.copyWith(
                color: colors.secondaryLabel,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}

class _BridgeStage extends StatelessWidget {
  const new({
    required this.progress,
    required this.flow,
    required this.bloom,
    required this.reducedMotion,
  });

  final LanSyncTransferProgress progress;
  final Animation<double> flow;
  final Animation<double> bloom;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final inset = width >= _wideStageThreshold
            ? _wideNodeInset
            : _compactNodeInset;
        final labelWidth = (inset * 2).clamp(84.0, 128.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              height: _bridgeStageHeight,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: Listenable.merge(<Listenable>[flow, bloom]),
                      builder: (context, _) => CustomPaint(
                        painter: LanSyncBridgePainter(
                          progress: progress,
                          colors: colors,
                          nodeInset: inset,
                          motion: LanSyncBridgeMotion(
                            flowPhase: flow.value,
                            bloomPhase: bloom.value,
                            reducedMotion: reducedMotion,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: inset - _nodePodSize / 2,
                    child: _DevicePod(
                      endpoint: progress.local,
                      accent: _localPodColor(colors),
                    ),
                  ),
                  _CenterNexus(progress: progress),
                  Positioned(
                    right: inset - _nodePodSize / 2,
                    child: _PeerPod(
                      peer: progress.peer,
                      accent: _peerPodColor(colors),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _DeviceCaption(
                  width: labelWidth,
                  title: progress.local.name,
                  subtitle: '当前设备',
                ),
                _DeviceCaption(
                  width: labelWidth,
                  title: progress.peer?.name ?? '等待连接',
                  subtitle: progress.peer == null ? '同网段设备' : '对端设备',
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Color _localPodColor(LexiColors colors) => switch (progress.phase) {
    LanSyncPhase.completed => colors.success,
    LanSyncPhase.failed => colors.secondaryLabel,
    _ => colors.accent,
  };

  Color _peerPodColor(LexiColors colors) => switch (progress.phase) {
    LanSyncPhase.completed => colors.success,
    LanSyncPhase.failed => colors.secondaryLabel,
    _ => colors.secondary,
  };
}

class _DevicePod extends StatelessWidget {
  const new({required this.endpoint, required this.accent, super.key});

  final LanSyncEndpoint endpoint;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      width: _nodePodSize,
      height: _nodePodSize,
      decoration: BoxDecoration(
        color: colors.card,
        shape: BoxShape.circle,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: LexiTint.subtle),
          shape: BoxShape.circle,
        ),
        child: Icon(
          endpoint.isDesktop ? LucideIcons.laptop : LucideIcons.smartphone,
          size: 20,
          color: accent,
        ),
      ),
    );
  }
}

class _PeerPod extends StatelessWidget {
  const new({required this.peer, required this.accent});

  final LanSyncEndpoint? peer;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final endpoint = peer;
    return AnimatedSwitcher(
      duration: LexiMotion.of(context, LexiMotion.standard),
      switchInCurve: LexiMotion.spring,
      child: endpoint == null
          ? Container(
              key: const ValueKey<String>('waiting-peer'),
              width: _nodePodSize,
              height: _nodePodSize,
              decoration: BoxDecoration(
                color: colors.fill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.radar,
                size: 18,
                color: colors.tertiaryLabel,
              ),
            )
          : _DevicePod(
              key: ValueKey<String>(endpoint.name),
              endpoint: endpoint,
              accent: accent,
            ),
    );
  }
}

class _CenterNexus extends StatelessWidget {
  const new({required this.progress});

  final LanSyncTransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final (
      Color bg,
      Color border,
      Color fg,
      IconData icon,
    ) = switch (progress.phase) {
      LanSyncPhase.completed => (
        colors.success,
        colors.success,
        Colors.white,
        LucideIcons.check,
      ),
      LanSyncPhase.failed => (
        Color.alphaBlend(
          colors.danger.withValues(alpha: LexiTint.tint),
          colors.card,
        ),
        colors.danger.withValues(alpha: LexiTint.border),
        colors.dangerText,
        LucideIcons.wifiOff,
      ),
      LanSyncPhase.merging => (
        colors.card,
        colors.accent.withValues(alpha: LexiTint.border),
        colors.accentText,
        LucideIcons.sparkles,
      ),
      LanSyncPhase.transferring => (
        colors.card,
        colors.accent.withValues(alpha: LexiTint.border),
        colors.accentText,
        switch (progress.direction) {
          LanSyncDirection.bidirectional => LucideIcons.arrowLeftRight,
          LanSyncDirection.pullOnly => LucideIcons.arrowLeft,
          LanSyncDirection.pushOnly => LucideIcons.arrowRight,
        },
      ),
      LanSyncPhase.waiting => (
        colors.card,
        colors.borderDefault,
        colors.secondaryLabel,
        LucideIcons.radio,
      ),
      _ => (
        colors.card,
        colors.borderDefault,
        colors.accentText,
        LucideIcons.link2,
      ),
    };

    return AnimatedContainer(
      duration: LexiMotion.of(context, LexiMotion.standard),
      curve: LexiMotion.spring,
      width: _nexusSize,
      height: _nexusSize,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: border),
      ),
      child: Icon(icon, size: 15, color: fg),
    );
  }
}

class _DeviceCaption extends StatelessWidget {
  const new({required this.width, required this.title, required this.subtitle});

  final double width;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return SizedBox(
      width: width,
      child: Column(
        children: <Widget>[
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LexiType.footnote.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
          ),
        ],
      ),
    );
  }
}

class _StageStatusStrip extends StatelessWidget {
  const new({required this.progress});

  final LanSyncTransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final isFailed = progress.phase == LanSyncPhase.failed;
    final isTransferring = progress.phase == LanSyncPhase.transferring;
    final pct = (progress.detail.bytes.overallProgress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _phaseCaption(progress),
          key: const Key('lanSyncTheaterStatus'),
          textAlign: TextAlign.center,
          style: LexiType.footnote.copyWith(
            color: isFailed ? colors.dangerText : colors.secondaryLabel,
            fontWeight: progress.isTerminal ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
        if (isTransferring) ...<Widget>[
          const SizedBox(height: LexiSpace.s8),
          Row(
            children: <Widget>[
              Expanded(
                child: LexiProgressBar(
                  value: progress.detail.bytes.overallProgress,
                  color: progress.direction == LanSyncDirection.pullOnly
                      ? colors.secondary
                      : colors.accent,
                ),
              ),
              const SizedBox(width: LexiSpace.s8),
              Text(
                '$pct%',
                style: LexiType.caption.copyWith(
                  color: colors.secondaryLabel,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CompletedSummaryStrip extends StatelessWidget {
  const new({required this.progress});

  final LanSyncTransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final local = progress.detail.localSummary;
    final peer = progress.detail.peerSummary;
    final items = <Widget>[
      if (local != null)
        Expanded(
          child: _SummaryTile(
            title: '本机',
            summary: local,
            accent: context.lexiColors.accentText,
          ),
        ),
      if (local != null && peer != null) const SizedBox(width: LexiSpace.s8),
      if (peer != null)
        Expanded(
          child: _SummaryTile(
            title: progress.peer?.name ?? '对端',
            summary: peer,
            accent: context.lexiColors.secondaryText,
          ),
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Row(children: items);
  }
}

class _SummaryTile extends StatelessWidget {
  const new({required this.title, required this.summary, required this.accent});

  final String title;
  final LanSyncDeltaSummary summary;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final line = summary.hasChanges
        ? '+${summary.addedWords} 词 · +${summary.addedLogs} 复习'
        : '已是最新';
    return Surface(
      variant: SurfaceVariant.inset,
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s12,
        vertical: LexiSpace.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LexiType.caption.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s2),
          Text(
            line,
            style: LexiType.footnote.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _TheaterActions extends StatelessWidget {
  const new({
    required this.progress,
    this.onCancel,
    this.onDismiss,
    this.onRetry,
  });

  final LanSyncTransferProgress progress;
  final VoidCallback? onCancel;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final compactText = LexiType.footnote.copyWith(fontWeight: FontWeight.w600);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        if (progress.isActive && onCancel != null)
          TextButton(
            key: const Key('lanSyncTheaterCancel'),
            style: TextButton.styleFrom(
              foregroundColor: colors.secondaryLabel,
              minimumSize: const Size(0, _compactActionHeight),
              padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s12),
              textStyle: compactText,
            ),
            onPressed: onCancel,
            child: const Text('取消同步'),
          ),
        if (progress.phase == LanSyncPhase.failed && onRetry != null)
          OutlinedButton.icon(
            key: const Key('lanSyncTheaterRetry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.label,
              side: BorderSide(color: colors.borderDefault),
              minimumSize: const Size(0, _compactActionHeight),
              padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s14),
              textStyle: compactText,
            ),
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: const Text('重试'),
          ),
        if (progress.isTerminal && onDismiss != null) ...<Widget>[
          const SizedBox(width: LexiSpace.s8),
          FilledButton(
            key: const Key('lanSyncTheaterDismiss'),
            style: FilledButton.styleFrom(
              elevation: 0,
              minimumSize: const Size(0, _compactActionHeight),
              padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s16),
              textStyle: compactText,
            ),
            onPressed: onDismiss,
            child: const Text('完成'),
          ),
        ],
      ],
    );
  }
}

String _modeBadgeLabel(LanSyncTransferProgress progress) {
  if (progress.phase == LanSyncPhase.waiting) {
    return progress.direction == LanSyncDirection.bidirectional
        ? '双向共享在线'
        : '只读共享在线';
  }
  if (progress.phase == LanSyncPhase.completed) {
    return progress.detail.isIncremental ? '增量同步完成' : '同步完成';
  }
  if (progress.phase == LanSyncPhase.failed) return '同步中断';
  final dir = switch (progress.direction) {
    LanSyncDirection.bidirectional => '双向',
    LanSyncDirection.pullOnly => '单向拉取',
    LanSyncDirection.pushOnly => '单向发送',
  };
  return progress.detail.isIncremental ? '$dir · 增量' : '$dir同步';
}

LexiBadgeTone _modeBadgeTone(LanSyncTransferProgress progress) =>
    switch (progress.phase) {
      LanSyncPhase.completed => LexiBadgeTone.success,
      LanSyncPhase.failed => LexiBadgeTone.danger,
      LanSyncPhase.waiting => LexiBadgeTone.neutral,
      _ => LexiBadgeTone.accent,
    };

String? _telemetryLabel(LanSyncTransferProgress progress) {
  final bytes = progress.detail.bytes;
  if (bytes.transferredWireBytes <= 0 && bytes.totalWireBytes <= 0) {
    return null;
  }
  final wire = bytes.transferredWireBytes > 0
      ? bytes.transferredWireBytes
      : bytes.totalWireBytes;
  final raw = bytes.uncompressedBytes;
  if (raw > wire && raw > 0) {
    final saved = (((raw - wire) * 100) / raw).round().clamp(1, 99);
    return '${formatBackupBytes(wire)} · 压缩省 $saved%';
  }
  return formatBackupBytes(wire);
}

String _phaseCaption(LanSyncTransferProgress progress) {
  switch (progress.phase) {
    case LanSyncPhase.waiting:
      return '正在局域网广播等待连接，在另一台设备搜索或输入地址即可接入';
    case LanSyncPhase.discovering:
      return '正在搜索同网段正在共享的 LexiLoop 设备…';
    case LanSyncPhase.connecting:
      return '正在与对端建立连接并核验配对码…';
    case LanSyncPhase.diffing:
      return progress.detail.isIncremental
          ? '已命中水位线，正在提取增量变更…'
          : '首次配对或全量同步，正在准备压缩快照…';
    case LanSyncPhase.transferring:
      return switch (progress.direction) {
        LanSyncDirection.bidirectional => '正在双向传输压缩增量流…',
        LanSyncDirection.pullOnly => '正在接收对端同步数据…',
        LanSyncDirection.pushOnly => '正在向对端发送同步数据…',
      };
    case LanSyncPhase.merging:
      return '正在本地增量落库并重排 FSRS 学习曲线…';
    case LanSyncPhase.completed:
      final local = progress.detail.localSummary;
      final peer = progress.detail.peerSummary;
      final changed =
          (local?.hasChanges ?? false) || (peer?.hasChanges ?? false);
      return changed ? '双端数据已融合收敛，进度完全一致' : '双端已是最新状态，无需变更';
    case LanSyncPhase.failed:
      final code = progress.detail.errorCode;
      return (code == null
              ? null
              : AppErrorCode.fromCode(code)?.defaultMessage) ??
          AppErrorCode.lanSyncRequestFailed.defaultMessage;
    case LanSyncPhase.idle:
      return '';
  }
}
