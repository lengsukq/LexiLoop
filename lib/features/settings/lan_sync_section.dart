/// 局域网同步设置分组。
///
/// 整合「本机共享（服务端）」与「连接设备同步（客户端）」，内置：
/// - v2 WebSocket 双向增量同步 + GZip 压缩 + 双端实时「词环共振桥」动画；
/// - 主机端共享策略切换（双向增量合并 / 仅发送只读）；
/// - 拉取端三档模式（双向 / 合并 / 覆盖）、自动搜索 + 手动输入 IP 直连；
/// - 上次同步状态行（时间、对端、失败原因）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/platform.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_session_client.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/features/settings/backup_size_label.dart';
import 'package:lexiloop/features/settings/data_invalidation.dart';
import 'package:lexiloop/features/settings/lan_sync/lan_sync_dialogs.dart';
import 'package:lexiloop/features/settings/lan_sync/lan_sync_theater.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_providers.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_pull_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_share_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_haptics.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/inline_notice.dart';
import 'package:lexiloop/ui/widgets/lexi_confirm_sheet.dart';
import 'package:lexiloop/ui/widgets/lexi_pressable.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 局域网覆盖拉取确认按钮的稳定 Key。
const Key lanSyncPullConfirmButtonKey = Key('lanSyncPullConfirmButton');

/// 配对码的展示字距。
const double lanSyncCodeLetterSpacing = 6;

/// 分区内紧凑按钮高度。
const double _compactButtonHeight = 38;

/// 分区切分两列表单的宽度阈值。
const double _twoColBreakpoint = 420;

/// 设备卡片左侧图标块尺寸。
const double _hostIconBoxSize = 36;

/// 局域网同步分组。
class LanSyncSection extends ConsumerStatefulWidget {
  /// 创建局域网同步分组。
  const new({super.key});

  @override
  ConsumerState<LanSyncSection> createState() => _LanSyncSectionState();
}

class _LanSyncSectionState extends ConsumerState<LanSyncSection> {
  late final TextEditingController _deviceName;
  late final TextEditingController _port;

  bool _seeded = false;
  bool _busy = false;
  LanSyncPullMode _mode = LanSyncPullMode.merge;
  LanSyncSharePolicy _sharePolicy = LanSyncSharePolicy.bidirectional;
  LanSyncDiscoveryResult? _found;
  String? _note;
  LanSyncTransferProgress? _clientProgress;
  LanSyncCancelSignal? _cancelSignal;
  DiscoveredLanHost? _lastTarget;
  String? _lastCode;
  int _observedHostRevision = 0;

  @override
  void initState() {
    super.initState();
    _deviceName = TextEditingController();
    _port = TextEditingController();
    ref.listenManual(appSettingsProvider, (previous, next) {
      final loaded = next.value;
      if (loaded == null || _seeded) return;
      _seed(loaded.raw[lanSyncSettingsKey]);
    }, fireImmediately: true);
    ref.listenManual(lanSyncShareProvider, (previous, next) {
      final revision = next.value?.dataRevision ?? 0;
      if (revision <= _observedHostRevision) return;
      _observedHostRevision = revision;
      invalidateLocalData(ref);
      ref.invalidate(appSettingsProvider);
    });
  }

  void _seed(Object? raw) {
    _seeded = true;
    final settings = lanSyncSettingsFromRaw(
      raw,
      fallbackDeviceName: defaultLanSyncDeviceName(
        isDesktop: PlatformCaps.isDesktop,
      ),
    );
    _deviceName.text = settings.deviceName;
    _port.text = '${settings.port}';
    _mode = settings.pullMode;
    _sharePolicy = settings.sharePolicy;
  }

  @override
  void dispose() {
    _cancelSignal?.cancel();
    _deviceName.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final share = ref.watch(lanSyncShareProvider);
    final rawSettings = ref
        .watch(appSettingsProvider)
        .value
        ?.raw[lanSyncSettingsKey];
    final lanSettings = lanSyncSettingsFromRaw(
      rawSettings,
      fallbackDeviceName: defaultLanSyncDeviceName(
        isDesktop: PlatformCaps.isDesktop,
      ),
    );
    final sharing = share.value?.isSharing ?? false;

    return SectionCard(
      title: '局域网同步',
      icon: LucideIcons.wifi,
      tone: LexiTone.mint,
      subtitle: '同一局域网设备直连增量同步，不经过任何服务器，自动压缩且只传变更。',
      child: PlatformCaps.isWeb
          ? Text(
              AppErrorCode.lanSyncUnsupported.defaultMessage,
              key: const Key('lanSyncUnsupported'),
              style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _sharePanel(share, sharing: sharing),
                const SizedBox(height: LexiSpace.s12),
                _pullPanel(lanSettings),
              ],
            ),
    );
  }

  Widget _sharePanel(
    AsyncValue<LanSyncShareSession?> share, {
    required bool sharing,
  }) {
    final session = share.value;
    final editable = session == null || !session.isSharing;
    return Surface(
      variant: SurfaceVariant.inset,
      padding: const EdgeInsets.all(LexiSpace.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SubPanelHeader(
            icon: LucideIcons.radio,
            tone: LexiTone.mint,
            title: '本机共享',
            trailing: LexiBadge(
              label: sharing ? '共享在线' : '等待开启',
              tone: sharing ? LexiBadgeTone.success : LexiBadgeTone.neutral,
            ),
          ),
          const SizedBox(height: LexiSpace.s12),
          _shareFields(enabled: editable),
          const SizedBox(height: LexiSpace.s12),
          _sharePolicyAndStart(share, editable: editable),
          ..._shareBody(share),
        ],
      ),
    );
  }

  Widget _shareFields({required bool enabled}) {
    final nameField = _LanSyncTextField(
      fieldKey: const Key('lanSyncDeviceNameField'),
      label: '设备名',
      hint: '对方搜索时看到的名字',
      controller: _deviceName,
      enabled: enabled,
      onChanged: (value) => unawaited(
        ref
            .read<LanSyncStateStore>(lanSyncStateStoreProvider)
            .setDeviceName(value),
      ),
    );
    final portField = _LanSyncTextField(
      fieldKey: const Key('lanSyncPortField'),
      label: '端口',
      hint: '$lanSyncDefaultPort',
      controller: _port,
      enabled: enabled,
      keyboardType: TextInputType.number,
      onChanged: (value) => unawaited(
        ref
            .read<LanSyncStateStore>(lanSyncStateStoreProvider)
            .setPort(parseLanSyncPort(int.tryParse(value.trim()))),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _twoColBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 3, child: nameField),
              const SizedBox(width: LexiSpace.s8),
              Expanded(flex: 2, child: portField),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            nameField,
            const SizedBox(height: LexiSpace.s8),
            portField,
          ],
        );
      },
    );
  }

  Widget _sharePolicyAndStart(
    AsyncValue<LanSyncShareSession?> share, {
    required bool editable,
  }) {
    final showStart = !share.isLoading && editable;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: LexiSpace.s8,
      runSpacing: LexiSpace.s8,
      children: <Widget>[
        _sharePolicySelector(enabled: editable),
        if (showStart) _startButton(),
      ],
    );
  }

  Widget _sharePolicySelector({required bool enabled}) =>
      SegmentedButton<LanSyncSharePolicy>(
        key: const Key('lanSyncSharePolicy'),
        style: _compactSegmentStyle(),
        segments: const <ButtonSegment<LanSyncSharePolicy>>[
          ButtonSegment<LanSyncSharePolicy>(
            value: LanSyncSharePolicy.bidirectional,
            label: Text('允许双向合并'),
            icon: Icon(LucideIcons.arrowLeftRight, size: 14),
          ),
          ButtonSegment<LanSyncSharePolicy>(
            value: LanSyncSharePolicy.readOnly,
            label: Text('仅发送（只读）'),
            icon: Icon(LucideIcons.shieldCheck, size: 14),
          ),
        ],
        selected: <LanSyncSharePolicy>{_sharePolicy},
        onSelectionChanged: enabled ? _selectSharePolicy : null,
      );

  List<Widget> _shareBody(AsyncValue<LanSyncShareSession?> share) {
    if (share.isLoading) {
      return const <Widget>[
        SizedBox(height: LexiSpace.s10),
        LinearProgressIndicator(minHeight: LexiSpace.s2),
      ];
    }
    if (share.error case final error?) {
      return <Widget>[
        const SizedBox(height: LexiSpace.s10),
        InlineNotice(
          key: const Key('lanSyncShareError'),
          message: error is AppError ? error.message : '开启共享失败：$error',
        ),
      ];
    }
    final session = share.value;
    if (session == null) return const <Widget>[];
    if (!session.isSharing) return _lockedOutNotice();
    return _activeShareBody(session);
  }

  List<Widget> _lockedOutNotice() => <Widget>[
    const SizedBox(height: LexiSpace.s10),
    InlineNotice(
      key: const Key('lanSyncLockedOut'),
      message: AppErrorCode.lanSyncCodeLockedOut.defaultMessage,
    ),
  ];

  List<Widget> _activeShareBody(LanSyncShareSession session) => <Widget>[
    const SizedBox(height: LexiSpace.s12),
    _hostTheater(session),
    const SizedBox(height: LexiSpace.s10),
    LanSyncPairingCodeCard(
      code: session.pairingCode,
      meta: (
        address: session.baseUri.toString(),
        servedCount: session.servedCount,
      ),
      onCopy: () => _copyCode(session.pairingCode),
      onStop: _busy ? null : _stopSharing,
    ),
  ];

  Widget _hostTheater(LanSyncShareSession session) {
    final progress =
        session.liveProgress ??
        LanSyncTransferProgress(
          phase: LanSyncPhase.waiting,
          direction: session.sharePolicy == LanSyncSharePolicy.bidirectional
              ? LanSyncDirection.bidirectional
              : LanSyncDirection.pushOnly,
          local: LanSyncEndpoint(
            name: session.deviceName,
            deviceKind: session.deviceKind,
            address: session.baseUri.authority,
          ),
        );
    return LanSyncTheater(
      progress: progress,
      onDismiss: session.liveProgress?.isTerminal ?? false
          ? () => ref.read(lanSyncShareProvider.notifier).dismissLiveProgress()
          : null,
    );
  }

  Widget _startButton() => FilledButton.icon(
    key: const Key('lanSyncStartShare'),
    style: _compactFilledStyle(),
    onPressed: _busy ? null : _startSharing,
    icon: const Icon(LucideIcons.wifi, size: 15),
    label: const Text('开启共享'),
  );

  Widget _pullPanel(LanSyncSettings settings) => Surface(
    variant: SurfaceVariant.inset,
    padding: const EdgeInsets.all(LexiSpace.s14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SubPanelHeader(
          icon: LucideIcons.arrowLeftRight,
          tone: LexiTone.sky,
          title: '连接局域网设备',
          caption: '推荐双向模式，一次配对两边一致',
        ),
        const SizedBox(height: LexiSpace.s8),
        LanSyncStatusLine(settings: settings),
        const SizedBox(height: LexiSpace.s10),
        ..._modeBlock(),
        if (_clientProgress case final live?) ...<Widget>[
          const SizedBox(height: LexiSpace.s12),
          LanSyncTheater(
            progress: live,
            onCancel: live.isActive ? _cancelSync : null,
            onDismiss: live.isTerminal
                ? () => setState(() => _clientProgress = null)
                : null,
            onRetry:
                live.phase == LanSyncPhase.failed &&
                    _lastTarget != null &&
                    _lastCode != null
                ? () => unawaited(_executeSync(_lastTarget!, _lastCode!, _mode))
                : null,
          ),
        ],
        const SizedBox(height: LexiSpace.s12),
        _pullActionRow(),
        ..._discoveryResult(),
      ],
    ),
  );

  Widget _pullActionRow() => Wrap(
    spacing: LexiSpace.s8,
    runSpacing: LexiSpace.s8,
    children: <Widget>[
      FilledButton.icon(
        key: const Key('lanSyncDiscover'),
        style: _compactFilledStyle(),
        onPressed: _busy ? null : _discover,
        icon: const Icon(LucideIcons.search, size: 15),
        label: Text(_busy ? '搜索中…' : '搜索设备'),
      ),
      OutlinedButton.icon(
        key: const Key('lanSyncManualConnect'),
        style: _compactOutlinedStyle(),
        onPressed: _busy ? null : _manualConnect,
        icon: const Icon(LucideIcons.globe, size: 15),
        label: const Text('手动输入地址'),
      ),
    ],
  );

  List<Widget> _modeBlock() => <Widget>[
    SegmentedButton<LanSyncPullMode>(
      key: const Key('lanSyncPullMode'),
      style: _compactSegmentStyle(),
      segments: _modeSegments,
      selected: <LanSyncPullMode>{_mode},
      onSelectionChanged: _selectMode,
    ),
    const SizedBox(height: LexiSpace.s6),
    Text(
      _modeHint(_mode),
      key: const Key('lanSyncPullModeHint'),
      style: LexiType.caption.copyWith(
        color: _mode == LanSyncPullMode.replace
            ? context.lexiColors.dangerText
            : context.lexiColors.secondaryLabel,
      ),
    ),
  ];

  static const List<ButtonSegment<LanSyncPullMode>> _modeSegments =
      <ButtonSegment<LanSyncPullMode>>[
        ButtonSegment<LanSyncPullMode>(
          value: LanSyncPullMode.bidirectional,
          label: Text('双向'),
          icon: Icon(LucideIcons.arrowLeftRight, size: 14),
        ),
        ButtonSegment<LanSyncPullMode>(
          value: LanSyncPullMode.merge,
          label: Text('合并'),
          icon: Icon(LucideIcons.merge, size: 14),
        ),
        ButtonSegment<LanSyncPullMode>(
          value: LanSyncPullMode.replace,
          label: Text('覆盖'),
          icon: Icon(LucideIcons.replace, size: 14),
        ),
      ];

  String _modeHint(LanSyncPullMode mode) => switch (mode) {
    LanSyncPullMode.bidirectional => '双向：一次配对互相增量合并，两边都拿到最新词条与复习记录，一条不删。',
    LanSyncPullMode.merge => '合并：把对方的词条与作答并进来，本机现有数据全部保留。',
    LanSyncPullMode.replace => '覆盖：用对方的数据整体替换本机，本机数据不保留、无法撤销。',
  };

  void _selectMode(Set<LanSyncPullMode> selection) {
    LexiHaptics.selection();
    setState(() => _mode = selection.first);
    unawaited(
      ref
          .read<LanSyncStateStore>(lanSyncStateStoreProvider)
          .setPullMode(selection.first),
    );
  }

  void _selectSharePolicy(Set<LanSyncSharePolicy> selection) {
    LexiHaptics.selection();
    setState(() => _sharePolicy = selection.first);
    unawaited(
      ref
          .read<LanSyncStateStore>(lanSyncStateStoreProvider)
          .setSharePolicy(selection.first),
    );
  }

  List<Widget> _discoveryResult() {
    final colors = context.lexiColors;
    final found = _found;
    final note = _note;
    return <Widget>[
      if (note != null) ...<Widget>[
        const SizedBox(height: LexiSpace.s10),
        InlineNotice(
          key: const Key('lanSyncDiscoveryNote'),
          message: note,
          tone: InlineNoticeTone.warning,
        ),
      ],
      if (found != null && found.hosts.isEmpty) ...<Widget>[
        const SizedBox(height: LexiSpace.s10),
        Text(
          AppErrorCode.lanSyncHostNotFound.defaultMessage,
          key: const Key('lanSyncEmptyHosts'),
          style: LexiType.caption.copyWith(color: colors.secondaryLabel),
        ),
      ],
      if (found != null && found.hosts.isNotEmpty) ...<Widget>[
        const SizedBox(height: LexiSpace.s10),
        for (var i = 0; i < found.hosts.length; i += 1) ...<Widget>[
          if (i > 0) const SizedBox(height: LexiSpace.s6),
          _hostTile(found.hosts[i], colors),
        ],
      ],
    ];
  }

  Widget _hostTile(DiscoveredLanHost host, LexiColors colors) =>
      _DiscoveredHostTile(
        key: Key('lanSyncHost-${host.address}'),
        host: host,
        onTap: _busy ? null : () => _pullFrom(host),
      );

  ButtonStyle _compactFilledStyle() => FilledButton.styleFrom(
    elevation: 0,
    minimumSize: const Size(0, _compactButtonHeight),
    padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s14),
    textStyle: LexiType.footnote.copyWith(fontWeight: FontWeight.w600),
  );

  ButtonStyle _compactOutlinedStyle() {
    final colors = context.lexiColors;
    return OutlinedButton.styleFrom(
      foregroundColor: colors.label,
      side: BorderSide(color: colors.borderDefault),
      minimumSize: const Size(0, _compactButtonHeight),
      padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s14),
      textStyle: LexiType.footnote.copyWith(fontWeight: FontWeight.w600),
    );
  }

  ButtonStyle _compactSegmentStyle() => const ButtonStyle(
    minimumSize: WidgetStatePropertyAll<Size>(Size(0, _compactButtonHeight)),
    padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: LexiSpace.s12),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  Future<void> _startSharing() async {
    LexiHaptics.light();
    setState(() => _busy = true);
    try {
      await ref.read(lanSyncShareProvider.notifier).start();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopSharing() async {
    setState(() => _busy = true);
    try {
      await ref.read(lanSyncShareProvider.notifier).stop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyCode(String code) async {
    LexiHaptics.light();
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: code));
    messenger.showSnackBar(const SnackBar(content: Text('配对码已复制。')));
  }

  Future<void> _discover() async {
    setState(() {
      _busy = true;
      _note = null;
      _found = null;
    });
    try {
      final result = await ref
          .read(lanSyncPullServiceProvider)
          .discover(
            excludeInstanceId: ref.read(lanSyncShareProvider).value?.instanceId,
          );
      if (!mounted) return;
      setState(() {
        _found = result;
        _note = result.incompatibleHostCount > 0 && result.hosts.isEmpty
            ? AppErrorCode.lanSyncProtocolMismatch.defaultMessage
            : null;
      });
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() => _note = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manualConnect() async {
    final host = await showDialog<DiscoveredLanHost>(
      context: context,
      builder: (_) => const LanSyncManualAddressDialog(),
    );
    if (host == null || !mounted) return;
    await _pullFrom(host);
  }

  Future<void> _pullFrom(DiscoveredLanHost host) async {
    final mode = _mode;
    final code = await showDialog<String>(
      context: context,
      builder: (_) => LanSyncPairingCodeDialog(host: host),
    );
    if (code == null || !mounted) return;
    if (await _confirmPull(host, mode) != true || !mounted) return;
    await _executeSync(host, code, mode);
  }

  Future<void> _executeSync(
    DiscoveredLanHost host,
    String code,
    LanSyncPullMode mode,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final cancel = LanSyncCancelSignal();
    setState(() {
      _busy = true;
      _cancelSignal = cancel;
      _lastTarget = host;
      _lastCode = code;
    });
    try {
      final result = await ref
          .read(lanSyncPullServiceProvider)
          .pull(
            host: host,
            pairingCode: code,
            mode: mode,
            cancelSignal: cancel,
            onProgress: (progress) {
              if (mounted) setState(() => _clientProgress = progress);
            },
          );
      if (!mounted) return;
      invalidateLocalData(ref);
      messenger.showSnackBar(
        SnackBar(content: Text(_pullSummary(host, result))),
      );
      _seeded = false;
      ref.invalidate(appSettingsProvider);
      setState(() => _found = null);
    } on AppError catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancelSignal = null;
        });
      }
    }
  }

  void _cancelSync() => _cancelSignal?.cancel();

  Future<bool?> _confirmPull(DiscoveredLanHost host, LanSyncPullMode mode) {
    if (mode == LanSyncPullMode.bidirectional) {
      return showLexiConfirmSheet(
        context,
        title: '与 ${_hostLabel(host)} 双向增量同步？',
        body:
            '一次配对即可交换双方的词条、词典内容、作答记录与会话历史，'
            '只传输上次同步以来的变更部分并自动压缩。\n\n'
            '双方现有数据全部保留，交错复习过的词会按完整历史重新排期；'
            '凭据与设备名不会被覆盖。',
        confirmLabel: '开始双向同步',
        confirmButtonKey: const Key('lanSyncMergeConfirm'),
      );
    }
    if (mode == LanSyncPullMode.merge) {
      return showLexiConfirmSheet(
        context,
        title: '合并 ${_hostLabel(host)} 的数据？',
        body:
            '会把对方的词条、词典内容、作答记录与会话历史并进本机。\n\n'
            '本机现有的数据全部保留；两边都复习过的词，会按合并后的完整'
            '历史重新排期。\n\n'
            '凭据（WebDAV 密码、AI Key）与本机的设备名、端口不会被对方覆盖。',
        confirmLabel: '合并',
        confirmButtonKey: const Key('lanSyncMergeConfirm'),
      );
    }
    return showLexiConfirmSheet(
      context,
      title: '用 ${_hostLabel(host)} 的数据覆盖本地？',
      body:
          '将下载对方的完整备份，并整体替换本机全部词条、学习记录、'
          '导入历史与设置。本机当前的数据不会保留，也无法撤销。\n\n'
          '建议先在「备份与导入」里导出本机备份留个底。\n\n'
          '如果只是想汇总两台设备的进度，请改用「双向」或「合并」。',
      confirmLabel: '覆盖恢复',
      destructive: true,
      confirmButtonKey: lanSyncPullConfirmButtonKey,
    );
  }

  String _pullSummary(DiscoveredLanHost host, LanSyncPullResult result) {
    final label = _hostLabel(host);
    final wire = result.transferredWireBytes > 0
        ? '（传输 ${formatBackupBytes(result.transferredWireBytes)}）'
        : '';
    if (result.mode == LanSyncPullMode.bidirectional) {
      return '已与 $label 双向同步：本机 +${result.addedWords} 词/+${result.addedLogs} '
          '作答，对端 +${result.peerAddedWords} 词/+${result.peerAddedLogs} '
          '作答$wire';
    }
    if (result.mode == LanSyncPullMode.merge) {
      return '已从 $label 合并：新增 ${result.addedWords} 个词条、'
          '${result.addedLogs} 条作答（本机共 ${result.wordCount} 个词条）$wire';
    }
    return '已从 $label 覆盖：${result.wordCount} 个词条、'
        '${result.writtenRows} 行$wire';
  }
}

String _hostLabel(DiscoveredLanHost host) =>
    host.deviceName.isEmpty ? host.address : host.deviceName;

class _SubPanelHeader extends StatelessWidget {
  const new({
    required this.icon,
    required this.tone,
    required this.title,
    this.caption,
    this.trailing,
  });

  final IconData icon;
  final LexiTone tone;
  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final style = context.lexiTones.styleOf(tone);
    return Row(
      children: <Widget>[
        Icon(icon, size: 15, color: style.foreground),
        const SizedBox(width: LexiSpace.s6),
        Text(
          title,
          style: LexiType.body.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: LexiSpace.s8),
        if (trailing != null) ...<Widget>[
          const Spacer(),
          trailing!,
        ] else if (caption != null)
          Expanded(
            child: Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
            ),
          ),
      ],
    );
  }
}

class _DiscoveredHostTile extends StatelessWidget {
  const new({required this.host, required this.onTap, super.key});

  final DiscoveredLanHost host;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final tone = context.lexiTones.styleOf(LexiTone.sky);
    final icon = host.deviceKind == lanSyncDeviceKindDesktop
        ? LucideIcons.laptop
        : host.deviceKind == lanSyncDeviceKindMobile
        ? LucideIcons.smartphone
        : LucideIcons.monitorSmartphone;
    return LexiPressable(
      borderRadius: BorderRadius.circular(LexiRadius.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s12,
          vertical: LexiSpace.s10,
        ),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(LexiRadius.md),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: _hostIconBoxSize,
              height: _hostIconBoxSize,
              decoration: BoxDecoration(
                color: tone.background,
                borderRadius: BorderRadius.circular(LexiRadius.sm),
              ),
              child: Icon(icon, size: 17, color: tone.foreground),
            ),
            const SizedBox(width: LexiSpace.s10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _hostLabel(host),
                    style: LexiType.body.copyWith(
                      color: colors.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${host.address}:${host.port}',
                    style: LexiType.caption.copyWith(
                      color: colors.secondaryLabel,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            LexiBadge(
              label: host.allowsBidirectional ? '双向' : '只读',
              tone: host.allowsBidirectional
                  ? LexiBadgeTone.accent
                  : LexiBadgeTone.neutral,
            ),
            const SizedBox(width: LexiSpace.s6),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: colors.tertiaryLabel,
            ),
          ],
        ),
      ),
    );
  }
}

class _LanSyncTextField extends StatelessWidget {
  const new({
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
    this.keyboardType,
  });

  final Key fieldKey;
  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: LexiType.caption.copyWith(
            color: colors.secondaryLabel,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: LexiSpace.s4),
        TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          autocorrect: false,
          keyboardType: keyboardType,
          style: LexiType.body.copyWith(color: colors.label),
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            fillColor: enabled ? colors.card : colors.fill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s12,
              vertical: LexiSpace.s10,
            ),
            hintText: hint,
            hintStyle: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
          ),
        ),
      ],
    );
  }
}
