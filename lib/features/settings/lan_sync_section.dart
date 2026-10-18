/// 局域网同步设置分组。
///
/// **两块内容、一张卡片**：上面是「本机共享（发送）」，下面是「从局域网设备
/// 拉取（接收）」。它们共用同一份设置（设备名、端口），拆成两张卡片会让
/// 「端口填了但没开共享」这种状态看起来像两件互不相关的事。
///
/// **为什么与远程备份（WebDAV）并列而不是合并**：两者是同一件事的两种交付
/// 方式——一个经服务器中转、换机可用，一个在局域网直连、不依赖任何第三方。
/// 用户的取舍（要不要为了换机而配一台 WebDAV）需要它们各自可读。
///
/// **共享的说明为什么占了一整段**：这是全应用唯一一个「别的设备可以读走你
/// 全部数据」的功能，用户必须在按下按钮之前就知道它做什么、不做什么。
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
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/features/settings/data_invalidation.dart';
import 'package:lexiloop/features/settings/remote_backup_section.dart'
    show restoreConfirmKeyword;
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/features/settings/typed_confirm_dialog.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_providers.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_pull_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_share_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 设备发现对话框的宽度（固定尺寸，不是间距——不参与 LexiSpace 音阶）。
const double lanSyncHostPickerWidth = 420;

/// 配对码的展示字距。
///
/// 6 位数字要能被一眼分组读出来，靠拉开字距比插入分隔符更稳
/// （对方照抄时不会把分隔符也抄进去）。
const double lanSyncCodeLetterSpacing = 6;

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

  /// 当前选中的拉取模式。
  ///
  /// **同时存在状态里与设置表里**：设置表是持久化的真相，但这个字段让
  /// 「刚点完『覆盖』就点设备」不会读到还没落盘的旧值（`setPullMode` 是异步的）。
  /// 首帧与每次重灌设置时都从设置表同步回来。
  LanSyncPullMode _mode = LanSyncPullMode.merge;
  LanSyncDiscoveryResult? _found;
  String? _note;

  @override
  void initState() {
    super.initState();
    // 与远程备份同一套初始化：先建空控制器，等异步设置到了再灌初值，
    // 否则「打开设置页直接点搜索」会用上一份空设备名。
    _deviceName = TextEditingController();
    _port = TextEditingController();
    ref.listenManual(appSettingsProvider, (previous, next) {
      final loaded = next.value;
      if (loaded == null || _seeded) return;
      _seed(loaded.raw[lanSyncSettingsKey]);
    }, fireImmediately: true);
  }

  /// 把库里已有的配置灌进输入框。
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
  }

  @override
  void dispose() {
    _deviceName.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final share = ref.watch(lanSyncShareProvider);

    return SettingsSectionCard(
      title: '局域网同步',
      subtitle:
          '在同一局域网的两台设备之间直接搬运数据，不经过任何服务器。'
          '一台开启共享（只读），另一台输配对码把数据拉过来。',
      child: PlatformCaps.isWeb
          ? Text(
              AppErrorCode.lanSyncUnsupported.defaultMessage,
              key: const Key('lanSyncUnsupported'),
              style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ..._shareBlock(share),
                const SizedBox(height: LexiSpace.s16),
                const Divider(),
                const SizedBox(height: LexiSpace.s16),
                ..._pullBlock(),
              ],
            ),
    );
  }

  /// 本机共享（发送）那一块。
  List<Widget> _shareBlock(AsyncValue<LanSyncShareSession?> share) {
    final session = share.value;
    return <Widget>[
      ..._shareIntro(),
      ..._shareFields(enabled: session == null),
      const SizedBox(height: LexiSpace.s12),
      ..._shareStatus(share),
    ];
  }

  /// 共享那块的标题与说明。
  List<Widget> _shareIntro() => <Widget>[
    const _BlockTitle(title: '本机共享（发送）'),
    const SizedBox(height: LexiSpace.s6),
    Text(
      '开启后，同网段的设备可以读到本机的一份完整备份。'
      '共享期间本机数据只会被读取，不会被修改；'
      '共享只在应用保持打开时有效。',
      style: LexiType.footnote.copyWith(
        color: context.lexiColors.secondaryLabel,
      ),
    ),
    const SizedBox(height: LexiSpace.s12),
  ];

  /// 设备名与端口两行输入。
  ///
  /// 共享进行中一律禁用：改端口不会对已经监听的套接字生效，
  /// 「改了没反应」比「不能改」更难理解。
  List<Widget> _shareFields({required bool enabled}) => <Widget>[
    _LanSyncTextField(
      fieldKey: const Key('lanSyncDeviceNameField'),
      label: '设备名',
      hint: '对方在搜索结果里看到的名字',
      controller: _deviceName,
      enabled: enabled,
      onChanged: (value) => unawaited(
        ref
            .read<LanSyncStateStore>(lanSyncStateStoreProvider)
            .setDeviceName(value),
      ),
    ),
    const SizedBox(height: LexiSpace.s8),
    _LanSyncTextField(
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
    ),
  ];

  /// 共享按钮与当前会话的展示。
  List<Widget> _shareStatus(AsyncValue<LanSyncShareSession?> share) {
    final session = share.value;
    if (share.isLoading) {
      return <Widget>[const LinearProgressIndicator(minHeight: LexiSpace.s2)];
    }
    final error = share.error;
    if (error != null) {
      return <Widget>[
        Text(
          error is AppError ? error.message : '开启共享失败：$error',
          key: const Key('lanSyncShareError'),
          style: LexiType.footnote.copyWith(
            color: context.lexiColors.dangerText,
          ),
        ),
        const SizedBox(height: LexiSpace.s8),
        _startButton(),
      ];
    }
    if (session == null) return <Widget>[_startButton()];
    if (!session.isSharing) return _lockedOutBlock();
    return <Widget>[..._codeBlock(session), ..._sessionActions(session)];
  }

  /// 因配对码连续错误而自动停止共享时的提示。
  List<Widget> _lockedOutBlock() => <Widget>[
    Text(
      AppErrorCode.lanSyncCodeLockedOut.defaultMessage,
      key: const Key('lanSyncLockedOut'),
      style: LexiType.footnote.copyWith(color: context.lexiColors.dangerText),
    ),
    const SizedBox(height: LexiSpace.s8),
    _startButton(),
  ];

  /// 配对码与地址。
  List<Widget> _codeBlock(LanSyncShareSession session) {
    final colors = context.lexiColors;
    return <Widget>[
      Text(
        '配对码',
        style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
      ),
      const SizedBox(height: LexiSpace.s4),
      Text(
        session.pairingCode,
        key: const Key('lanSyncPairingCode'),
        style: LexiType.title2.copyWith(
          color: colors.accentText,
          letterSpacing: lanSyncCodeLetterSpacing,
        ),
      ),
      const SizedBox(height: LexiSpace.s6),
      Text(
        '在另一台设备上输入这 6 位数字即可拉取。地址：${session.baseUri}',
        key: const Key('lanSyncShareAddress'),
        style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
      ),
      const SizedBox(height: LexiSpace.s2),
      Text(
        '已服务 ${session.servedCount} 次',
        key: const Key('lanSyncServedCount'),
        style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
      ),
      const SizedBox(height: LexiSpace.s12),
    ];
  }

  /// 会话进行中的两个动作。
  List<Widget> _sessionActions(LanSyncShareSession session) => <Widget>[
    OutlinedButton.icon(
      key: const Key('lanSyncCopyCode'),
      onPressed: () => _copyCode(session.pairingCode),
      icon: const Icon(LucideIcons.copy, size: 16),
      label: const Text('复制配对码'),
    ),
    const SizedBox(height: LexiSpace.s8),
    OutlinedButton.icon(
      key: const Key('lanSyncStopShare'),
      onPressed: _busy ? null : _stopSharing,
      icon: const Icon(LucideIcons.circleStop, size: 16),
      label: const Text('停止共享'),
    ),
  ];

  Widget _startButton() => FilledButton.icon(
    key: const Key('lanSyncStartShare'),
    onPressed: _busy ? null : _startSharing,
    icon: const Icon(LucideIcons.wifi, size: 16),
    label: const Text('开启共享'),
  );

  /// 从局域网设备拉取（接收）那一块。
  List<Widget> _pullBlock() => <Widget>[
    ..._pullIntro(),
    const SizedBox(height: LexiSpace.s12),
    ..._modeBlock(),
    const SizedBox(height: LexiSpace.s12),
    OutlinedButton.icon(
      key: const Key('lanSyncDiscover'),
      onPressed: _busy ? null : _discover,
      icon: const Icon(LucideIcons.search, size: 16),
      label: Text(_busy ? '搜索中…' : '搜索设备'),
    ),
    ..._discoveryResult(),
  ];

  /// 拉取那块的标题与说明。
  List<Widget> _pullIntro() => <Widget>[
    const _BlockTitle(title: '从局域网设备拉取（接收）'),
    const SizedBox(height: LexiSpace.s6),
    Text(
      '搜索同网段正在共享的设备，把它的数据搬到本机。两种方式的差别见下。',
      style: LexiType.footnote.copyWith(
        color: context.lexiColors.secondaryLabel,
      ),
    ),
  ];

  /// 「同步方式」两选一。
  ///
  /// **选择落盘**：用户的意图通常在几次同步里不变，记住它能少一次误选；
  /// 两种方式各自的确认门仍然保留，误选不会跨过那道门。
  List<Widget> _modeBlock() => <Widget>[
    SegmentedButton<LanSyncPullMode>(
      key: const Key('lanSyncPullMode'),
      segments: _modeSegments,
      selected: <LanSyncPullMode>{_mode},
      onSelectionChanged: _selectMode,
    ),
    const SizedBox(height: LexiSpace.s6),
    Text(
      _mode == LanSyncPullMode.merge ? _mergeHint : _replaceHint,
      key: const Key('lanSyncPullModeHint'),
      style: LexiType.footnote.copyWith(
        color: _mode == LanSyncPullMode.merge
            ? context.lexiColors.secondaryLabel
            : context.lexiColors.dangerText,
      ),
    ),
  ];

  /// 两个选项的文案。
  static const List<ButtonSegment<LanSyncPullMode>> _modeSegments =
      <ButtonSegment<LanSyncPullMode>>[
        ButtonSegment<LanSyncPullMode>(
          value: LanSyncPullMode.merge,
          label: Text('合并'),
          icon: Icon(LucideIcons.merge, size: 16),
        ),
        ButtonSegment<LanSyncPullMode>(
          value: LanSyncPullMode.replace,
          label: Text('覆盖'),
          icon: Icon(LucideIcons.arrowLeftRight, size: 16),
        ),
      ];

  /// 合并的说明。
  static const String _mergeHint = '合并：把对方的词条与作答并进来，本机现有数据全部保留。';

  /// 覆盖的说明。
  static const String _replaceHint = '覆盖：用对方的数据整体替换本机，本机数据不保留、无法撤销。';

  /// 记住选择并落盘。
  ///
  /// **先改状态再写库**：`setPullMode` 是异步的，而用户可能紧接着就点设备。
  /// 状态是这一次交互的真相，设置表只是持久化。
  void _selectMode(Set<LanSyncPullMode> selection) {
    setState(() => _mode = selection.first);
    unawaited(
      ref
          .read<LanSyncStateStore>(lanSyncStateStoreProvider)
          .setPullMode(selection.first),
    );
  }

  /// 搜索的提示、空态与结果列表。
  List<Widget> _discoveryResult() {
    final colors = context.lexiColors;
    final found = _found;
    final note = _note;
    return <Widget>[
      if (note != null) ...<Widget>[
        const SizedBox(height: LexiSpace.s8),
        Text(
          note,
          key: const Key('lanSyncDiscoveryNote'),
          style: LexiType.footnote.copyWith(color: colors.dangerText),
        ),
      ],
      if (found != null && found.hosts.isEmpty) ...<Widget>[
        const SizedBox(height: LexiSpace.s8),
        Text(
          AppErrorCode.lanSyncHostNotFound.defaultMessage,
          key: const Key('lanSyncEmptyHosts'),
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
      ],
      if (found != null)
        for (final host in found.hosts) _hostTile(host, colors),
    ];
  }

  /// 一台可拉取的设备。
  Widget _hostTile(DiscoveredLanHost host, LexiColors colors) => ListTile(
    key: Key('lanSyncHost-${host.address}'),
    contentPadding: EdgeInsets.zero,
    leading: const Icon(LucideIcons.monitorSmartphone),
    title: Text(_hostLabel(host)),
    subtitle: Text(
      '${host.address}:${host.port}',
      style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
    ),
    onTap: _busy ? null : () => _pullFrom(host),
  );

  /// 开启共享。
  Future<void> _startSharing() async {
    setState(() => _busy = true);
    try {
      await ref.read(lanSyncShareProvider.notifier).start();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 停止共享。
  Future<void> _stopSharing() async {
    setState(() => _busy = true);
    try {
      await ref.read(lanSyncShareProvider.notifier).stop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 复制配对码。
  Future<void> _copyCode(String code) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: code));
    messenger.showSnackBar(const SnackBar(content: Text('配对码已复制。')));
  }

  /// 搜索同网段的共享设备。
  Future<void> _discover() async {
    setState(() {
      _busy = true;
      _note = null;
      _found = null;
    });
    try {
      // 排除本机自己的共享会话：同一台设备既开着共享又点搜索时会收到自己。
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

  /// 选一台设备：输配对码 → 按当前模式确认 → 拉取。
  Future<void> _pullFrom(DiscoveredLanHost host) async {
    final mode = _mode;
    final code = await _askForCode(host);
    if (code == null || !mounted) return;
    if (await _confirmPull(host, mode) != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(lanSyncPullServiceProvider)
          .pull(host: host, pairingCode: code, mode: mode);
      if (!mounted) return;
      // 与本地导入、远端恢复同一条约定：整库被写之后必须显式失效缓存。
      invalidateLocalData(ref);
      messenger.showSnackBar(
        SnackBar(content: Text(_pullSummary(host, result))),
      );
      // 恢复会整体替换设置表，输入框要按恢复后的内容重新灌一次。
      _seeded = false;
      ref.invalidate(appSettingsProvider);
      setState(() => _found = null);
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 输入配对码。
  Future<String?> _askForCode(DiscoveredLanHost host) => showDialog<String>(
    context: context,
    builder: (dialogContext) => _PairingCodeDialog(host: host),
  );

  /// 拉取前的确认；门槛按模式区分。
  Future<bool?> _confirmPull(DiscoveredLanHost host, LanSyncPullMode mode) =>
      showDialog<bool>(
        context: context,
        builder: (dialogContext) => mode == LanSyncPullMode.merge
            ? _MergeConfirmDialog(host: host)
            : _ReplaceConfirmDialog(host: host),
      );

  /// 成功后的汇报文案。
  ///
  /// 两条模式的措辞刻意不同：合并说「新增」，覆盖说「覆盖」——
  /// 用户需要一眼分辨刚才那次到底是哪一种。
  String _pullSummary(DiscoveredLanHost host, LanSyncPullResult result) {
    final label = _hostLabel(host);
    if (result.mode == LanSyncPullMode.merge) {
      return '已从 $label 合并：新增 ${result.addedWords} 个词条、'
          '${result.addedLogs} 条作答（本机共 ${result.wordCount} 个词条）';
    }
    return '已从 $label 覆盖：${result.wordCount} 个词条、'
        '${result.writtenRows} 行';
  }
}

/// 展示用的设备名；没命名时退到地址。
String _hostLabel(DiscoveredLanHost host) =>
    host.deviceName.isEmpty ? host.address : host.deviceName;

/// 小标题。
class _BlockTitle extends StatelessWidget {
  const new({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: LexiType.callout.copyWith(
      color: context.lexiColors.label,
      fontWeight: FontWeight.w600,
    ),
  );
}

/// 普通文本输入行。
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
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      autocorrect: false,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: LexiType.body.copyWith(color: colors.tertiaryLabel),
        // 共享进行中改端口不会生效，禁用比「改了没反应」诚实。
        helperText: enabled ? null : '共享进行中不可修改',
        helperStyle: LexiType.footnote.copyWith(color: colors.secondaryLabel),
      ),
    );
  }
}

/// 输入配对码的对话框。
class _PairingCodeDialog extends StatefulWidget {
  const new({required this.host});

  final DiscoveredLanHost host;

  @override
  State<_PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<_PairingCodeDialog> {
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
    return AlertDialog(
      title: const Text('输入配对码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '对方设备「${_hostLabel(widget.host)}」的共享页面上显示着一个 '
            '6 位配对码。',
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

/// 合并前的确认。
///
/// **不要求敲关键字**：合并不是破坏性的——本机的词条、作答、会话一条都不会
/// 被删。给一个和「覆盖」同等强度的门槛只会训练用户无脑敲 `RESTORE`。
class _MergeConfirmDialog extends StatelessWidget {
  const new({required this.host});

  final DiscoveredLanHost host;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return AlertDialog(
      title: Text('合并 ${_hostLabel(host)} 的数据？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '会把对方的词条、词典内容、作答记录与会话历史并进本机。\n\n'
            '本机现有的数据全部保留；两边都复习过的词，会按合并后的完整'
            '历史重新排期。',
          ),
          const SizedBox(height: LexiSpace.s8),
          Text(
            '凭据（WebDAV 密码、AI Key）与本机的设备名、端口不会被对方覆盖。',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('lanSyncMergeConfirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('合并'),
        ),
      ],
    );
  }
}

/// 覆盖前的确认：说清不可撤销，并指出可以先导出一份留底。
class _ReplaceConfirmDialog extends StatelessWidget {
  const new({required this.host});

  final DiscoveredLanHost host;

  @override
  Widget build(BuildContext context) {
    return TypedConfirmDialog(
      title: '用 ${_hostLabel(host)} 的数据覆盖本地？',
      body:
          '将下载对方的完整备份，并整体替换本机全部词条、学习记录、'
          '导入历史与设置。本机当前的数据不会保留，也无法撤销。\n\n'
          '建议先在「备份与导入」里导出本机备份留个底。\n\n'
          '如果只是想汇总两台设备的进度，请改用「合并」。\n\n'
          '请输入 $restoreConfirmKeyword 以确认。',
      keyword: restoreConfirmKeyword,
      confirmLabel: '覆盖恢复',
      keyPrefix: 'lanSyncPullConfirm',
    );
  }
}
