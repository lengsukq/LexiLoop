/// 局域网同步相关弹窗与小组件（配对码展示条、配对码输入、手动地址直连、状态行）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 紧凑按钮高度（固定尺寸，非间距）。
const double _inlineButtonHeight = 34;

/// 状态点直径。
const double _statusDotSize = 7;

/// 配对码分组视觉卡片：将 6 位数字、地址、服务次数与操作收在同一块干净容器里。
class LanSyncPairingCodeCard extends StatelessWidget {
  /// 以配对码、可选连接元信息与操作回调构造。
  const new({
    required this.code,
    this.meta,
    this.onCopy,
    this.onStop,
    super.key,
  });

  /// 6 位配对码。
  final String code;

  /// 可选地址与已服务次数元信息。
  final ({String address, int servedCount})? meta;

  /// 点击复制配对码回调。
  final VoidCallback? onCopy;

  /// 点击停止共享回调。
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final formatted = code.length == lanSyncPairingCodeLength
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    return Container(
      padding: const EdgeInsets.all(LexiSpace.s12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _codeRow(colors, formatted),
          if (meta case final info?) ...<Widget>[
            const SizedBox(height: LexiSpace.s8),
            _metaRow(colors, info),
          ],
        ],
      ),
    );
  }

  Widget _codeRow(LexiColors colors, String formatted) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: LexiSpace.s8,
    runSpacing: LexiSpace.s8,
    children: <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '配对码',
            style: LexiType.caption.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(width: LexiSpace.s10),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s12,
              vertical: LexiSpace.s4,
            ),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: LexiTint.subtle),
              borderRadius: BorderRadius.circular(LexiRadius.sm),
              border: Border.all(
                color: colors.accent.withValues(alpha: LexiTint.border),
              ),
            ),
            child: Text(
              formatted,
              key: const Key('lanSyncPairingCode'),
              style: LexiType.title.copyWith(
                color: colors.accentText,
                letterSpacing: 3,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
      _inlineActions(colors),
    ],
  );

  Widget _inlineActions(LexiColors colors) {
    final style = LexiType.footnote.copyWith(fontWeight: FontWeight.w600);
    return Wrap(
      spacing: LexiSpace.s6,
      runSpacing: LexiSpace.s6,
      children: <Widget>[
        if (onCopy != null)
          OutlinedButton.icon(
            key: const Key('lanSyncCopyCode'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.label,
              side: BorderSide(color: colors.borderDefault),
              minimumSize: const Size(0, _inlineButtonHeight),
              padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s12),
              textStyle: style,
            ),
            onPressed: onCopy,
            icon: const Icon(LucideIcons.copy, size: 14),
            label: const Text('复制配对码'),
          ),
        if (onStop != null)
          TextButton.icon(
            key: const Key('lanSyncStopShare'),
            style: TextButton.styleFrom(
              foregroundColor: colors.dangerText,
              minimumSize: const Size(0, _inlineButtonHeight),
              padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s10),
              textStyle: style,
            ),
            onPressed: onStop,
            icon: const Icon(LucideIcons.circleStop, size: 14),
            label: const Text('停止共享'),
          ),
      ],
    );
  }

  Widget _metaRow(
    LexiColors colors,
    ({String address, int servedCount}) info,
  ) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    spacing: LexiSpace.s12,
    runSpacing: LexiSpace.s4,
    children: <Widget>[
      Text(
        '地址：${info.address}',
        key: const Key('lanSyncShareAddress'),
        style: LexiType.caption.copyWith(
          color: colors.secondaryLabel,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      Text(
        '已服务 ${info.servedCount} 次',
        key: const Key('lanSyncServedCount'),
        style: LexiType.caption.copyWith(
          color: colors.tertiaryLabel,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

/// 上次同步状态行（带语义状态点：显示上次成功时间/对端与上次失败原因）。
class LanSyncStatusLine extends StatelessWidget {
  /// 以局域网同步设置构造。
  const new({required this.settings, super.key});

  /// 当前局域网同步设置（含状态字段）。
  final LanSyncSettings settings;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final lastError = settings.lastError;
    final hasError = lastError != null && lastError.isNotEmpty;
    final lines = <String>[
      if (settings.lastSuccessAt case final at?)
        _successLine(at, settings.lastPeer)
      else
        '还没有局域网同步记录',
      if (hasError) '上次失败：${_errorLabel(lastError)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < lines.length; i += 1)
          Padding(
            padding: const EdgeInsets.only(bottom: LexiSpace.s2),
            child: Row(
              children: <Widget>[
                Container(
                  width: _statusDotSize,
                  height: _statusDotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dotColor(
                      colors,
                      isError: hasError && i == lines.length - 1,
                      hasSuccess: settings.lastSuccessAt != null,
                    ),
                  ),
                ),
                const SizedBox(width: LexiSpace.s8),
                Expanded(
                  child: Text(
                    lines[i],
                    key: Key('lanSyncStatus-$i'),
                    style: LexiType.caption.copyWith(
                      color: hasError && i == lines.length - 1
                          ? colors.dangerText
                          : colors.secondaryLabel,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _dotColor(
    LexiColors colors, {
    required bool isError,
    required bool hasSuccess,
  }) {
    if (isError) return colors.danger;
    if (hasSuccess) return colors.success;
    return colors.borderStrong;
  }

  String _successLine(int epochMs, String? peer) {
    final time = _formatSyncTime(epochMs);
    if (peer == null || peer.isEmpty) return '上次同步：$time';
    return '上次同步：$time · $peer';
  }

  String _errorLabel(String code) =>
      AppErrorCode.fromCode(code)?.defaultMessage ??
      AppErrorCode.lanSyncRequestFailed.defaultMessage;
}

/// 输入配对码的对话框。
class LanSyncPairingCodeDialog extends StatefulWidget {
  /// 以目标设备构造。
  const new({required this.host, super.key});

  /// 目标共享设备。
  final DiscoveredLanHost host;

  @override
  State<LanSyncPairingCodeDialog> createState() =>
      _LanSyncPairingCodeDialogState();
}

class _LanSyncPairingCodeDialogState extends State<LanSyncPairingCodeDialog> {
  final TextEditingController _code = TextEditingController();
  bool _matched = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final label = widget.host.deviceName.isEmpty
        ? widget.host.address
        : widget.host.deviceName;
    return AlertDialog(
      title: const Text('输入配对码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '对方设备「$label」的共享页面上显示着一个 6 位配对码。',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s12),
          TextField(
            key: const Key('lanSyncCodeField'),
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: lanSyncPairingCodeLength,
            decoration: const InputDecoration(hintText: '6 位数字'),
            onChanged: (value) => setState(
              () => _matched = value.trim().length == lanSyncPairingCodeLength,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('lanSyncCodeConfirm'),
          onPressed: _matched
              ? () => Navigator.of(context).pop(_code.text.trim())
              : null,
          child: const Text('下一步'),
        ),
      ],
    );
  }
}

/// 手动输入局域网地址直连的对话框（供 UDP 广播被路由器/VPN 拦截时使用）。
class LanSyncManualAddressDialog extends StatefulWidget {
  /// 创建手动直连对话框。
  const new({super.key});

  @override
  State<LanSyncManualAddressDialog> createState() =>
      _LanSyncManualAddressDialogState();
}

class _LanSyncManualAddressDialogState
    extends State<LanSyncManualAddressDialog> {
  final TextEditingController _address = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return AlertDialog(
      title: const Text('手动连接设备'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '若路由器或 VPN 拦截了自动搜索，可直接输入对方共享页面上的地址（如 192.168.1.8:8765）。',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s12),
          TextField(
            key: const Key('lanSyncManualAddressField'),
            controller: _address,
            autofocus: true,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: '192.168.1.8:$lanSyncDefaultPort',
              errorText: _error,
              prefixIcon: const Icon(LucideIcons.globe, size: 16),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('lanSyncManualAddressConfirm'),
          onPressed: _submit,
          child: const Text('连接'),
        ),
      ],
    );
  }

  void _submit() {
    final host = parseManualLanHost(_address.text);
    if (host == null) {
      setState(
        () => _error = AppErrorCode.lanSyncInvalidAddress.defaultMessage,
      );
      return;
    }
    Navigator.of(context).pop(host);
  }
}

String _formatSyncTime(int epochMs) {
  final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String pad(int value) => value.toString().padLeft(2, '0');
  final date = '${t.year}-${pad(t.month)}-${pad(t.day)}';
  return '$date ${pad(t.hour)}:${pad(t.minute)}';
}
