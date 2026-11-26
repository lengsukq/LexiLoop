/// Next.js 云端跨端同步设置分组。
///
/// 挂在「设置 → 数据管理」中，支持输入 Next.js 站点地址与登录密码，
/// 一键执行双向增量同步、单向拉取合并或云端覆盖本机（自动分片 + GZip 兼容 Vercel）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_client.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/models/cloud_sync_progress.dart';
import 'package:lexiloop/domain/models/cloud_sync_settings.dart';
import 'package:lexiloop/features/settings/backup_size_label.dart';
import 'package:lexiloop/features/settings/data_invalidation.dart';
import 'package:lexiloop/services/cloud_sync/cloud_sync_providers.dart';
import 'package:lexiloop/services/cloud_sync/cloud_sync_service.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_haptics.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/lexi_confirm_sheet.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 云端覆盖确认按钮的稳定 Key。
const Key cloudSyncReplaceConfirmButtonKey = Key(
  'cloudSyncReplaceConfirmButton',
);

const double _cloudTwoColBreakpoint = 440;
const double _cloudButtonHeight = 38;
const double _cloudStatusDotSize = 7;

/// Next.js 云端同步设置卡片。
class CloudSyncSection extends ConsumerStatefulWidget {
  /// 创建 Next.js 云端同步分组。
  const new({super.key});

  @override
  ConsumerState<CloudSyncSection> createState() => _CloudSyncSectionState();
}

class _CloudSyncSectionState extends ConsumerState<CloudSyncSection> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _password;

  bool _seeded = false;
  bool _busy = false;
  bool _obscurePassword = true;
  CloudSyncMode _mode = CloudSyncMode.bidirectional;
  CloudSyncProgress? _progress;
  CloudSyncCancelSignal? _cancelSignal;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController();
    _password = TextEditingController();
    ref.listenManual(appSettingsProvider, (previous, next) {
      final loaded = next.value;
      if (loaded == null || _seeded) return;
      _seed(loaded.raw[cloudSyncSettingsKey]);
    }, fireImmediately: true);
  }

  void _seed(Object? raw) {
    _seeded = true;
    final settings = cloudSyncSettingsFromRaw(raw);
    _baseUrl.text = settings.credential?.baseUrl ?? '';
    _password.text = settings.credential?.password ?? '';
    _mode = settings.mode;
  }

  @override
  void dispose() {
    _cancelSignal?.cancel();
    _baseUrl.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raw = ref.watch(appSettingsProvider).value?.raw[cloudSyncSettingsKey];
    final settings = cloudSyncSettingsFromRaw(raw);
    final configured = normalizeCloudSyncBaseUrl(_baseUrl.text) != null;

    return SectionCard(
      title: 'Next.js 云端同步',
      icon: LucideIcons.cloudCog,
      tone: LexiTone.sky,
      subtitle: '直连部署在 Vercel 或自托管的 Next.js 实例，GZip 分片双向增量互传。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _serverPanel(configured: configured),
          const SizedBox(height: LexiSpace.s10),
          _CloudStatusLine(settings: settings, configured: configured),
          if (_progress case final live?) ...<Widget>[
            const SizedBox(height: LexiSpace.s10),
            _CloudProgressBanner(progress: live),
          ],
          const SizedBox(height: LexiSpace.s12),
          _actionBar(configured: configured),
        ],
      ),
    );
  }

  Widget _serverPanel({required bool configured}) => Surface(
    variant: SurfaceVariant.inset,
    padding: const EdgeInsets.all(LexiSpace.s14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _panelHeader(configured: configured),
        const SizedBox(height: LexiSpace.s12),
        _credentialFields(),
        const SizedBox(height: LexiSpace.s12),
        _modeSelector(),
      ],
    ),
  );

  Widget _panelHeader({required bool configured}) => Row(
    children: <Widget>[
      Text(
        'Next.js 服务器',
        style: LexiType.body.copyWith(
          color: context.lexiColors.label,
          fontWeight: FontWeight.w600,
        ),
      ),
      const Spacer(),
      LexiBadge(
        label: configured ? '已配置' : '未配置',
        tone: configured ? LexiBadgeTone.success : LexiBadgeTone.neutral,
      ),
    ],
  );

  Widget _credentialFields() => LayoutBuilder(
    builder: (context, constraints) {
      final urlField = _CloudTextField(
        fieldKey: const Key('cloudSyncBaseUrlField'),
        label: '站点地址',
        hint: 'https://your-app.vercel.app',
        controller: _baseUrl,
        onChanged: (_) => _saveCredentials(),
      );
      final pwdField = _CloudTextField(
        fieldKey: const Key('cloudSyncPasswordField'),
        label: '登录密码（可选）',
        hint: 'LEXILOOP_PASSWORD',
        controller: _password,
        secret: (
          obscure: _obscurePassword,
          onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
        onChanged: (_) => _saveCredentials(),
      );
      if (constraints.maxWidth >= _cloudTwoColBreakpoint) {
        return Row(
          children: <Widget>[
            Expanded(flex: 3, child: urlField),
            const SizedBox(width: LexiSpace.s8),
            Expanded(flex: 2, child: pwdField),
          ],
        );
      }
      return Column(
        children: <Widget>[
          urlField,
          const SizedBox(height: LexiSpace.s8),
          pwdField,
        ],
      );
    },
  );

  Widget _modeSelector() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      SegmentedButton<CloudSyncMode>(
        key: const Key('cloudSyncModeSelector'),
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll<Size>(
            Size(0, _cloudButtonHeight),
          ),
          padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: LexiSpace.s12),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: _modeSegments,
        selected: <CloudSyncMode>{_mode},
        onSelectionChanged: _busy ? null : _selectMode,
      ),
      const SizedBox(height: LexiSpace.s6),
      Text(
        _modeHint(_mode),
        key: const Key('cloudSyncModeHint'),
        style: LexiType.caption.copyWith(
          color: _mode == CloudSyncMode.pullReplace
              ? context.lexiColors.dangerText
              : context.lexiColors.secondaryLabel,
        ),
      ),
    ],
  );

  Widget _actionBar({required bool configured}) {
    final colors = context.lexiColors;
    final compact = LexiType.footnote.copyWith(fontWeight: FontWeight.w600);
    final outlineStyle = OutlinedButton.styleFrom(
      foregroundColor: colors.label,
      disabledForegroundColor: colors.tertiaryLabel,
      side: BorderSide(
        color: configured ? colors.borderDefault : colors.borderSubtle,
      ),
      minimumSize: const Size(0, _cloudButtonHeight),
      padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s14),
      textStyle: compact,
    );
    return Wrap(
      spacing: LexiSpace.s8,
      runSpacing: LexiSpace.s8,
      children: <Widget>[
        FilledButton.icon(
          key: const Key('cloudSyncStartButton'),
          style: FilledButton.styleFrom(
            elevation: 0,
            minimumSize: const Size(0, _cloudButtonHeight),
            padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s14),
            textStyle: compact,
          ),
          onPressed: _busy || !configured ? null : _startSync,
          icon: const Icon(LucideIcons.refreshCw, size: 15),
          label: Text(_busy ? '同步中…' : '立即同步'),
        ),
        OutlinedButton.icon(
          key: const Key('cloudSyncTestButton'),
          style: outlineStyle,
          onPressed: _busy || !configured ? null : _testConnection,
          icon: const Icon(LucideIcons.plug, size: 15),
          label: const Text('测试连接'),
        ),
        if (_busy)
          OutlinedButton.icon(
            key: const Key('cloudSyncCancelButton'),
            style: outlineStyle,
            onPressed: () => _cancelSignal?.cancel(),
            icon: const Icon(LucideIcons.x, size: 15),
            label: const Text('取消'),
          ),
      ],
    );
  }

  void _saveCredentials() {
    setState(() {});
    unawaited(
      ref
          .read(cloudSyncStateStoreProvider)
          .saveCredential(baseUrl: _baseUrl.text, password: _password.text),
    );
  }

  void _selectMode(Set<CloudSyncMode> selection) {
    LexiHaptics.selection();
    setState(() => _mode = selection.first);
    unawaited(ref.read(cloudSyncStateStoreProvider).setMode(selection.first));
  }

  Future<void> _testConnection() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final reply = await ref
          .read(cloudSyncServiceProvider)
          .testConnection(
            overrideCredential: CloudSyncCredential(
              baseUrl: _baseUrl.text,
              password: _password.text,
            ),
          );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('连接成功：云端当前共 ${reply.wordCount} 个词条。')),
      );
    } on AppError catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startSync() async {
    if (_mode == CloudSyncMode.pullReplace && !await _confirmReplace()) return;
    if (!mounted) return;
    await _runSync();
  }

  Future<void> _runSync() async {
    LexiHaptics.light();
    final messenger = ScaffoldMessenger.of(context);
    final signal = CloudSyncCancelSignal();
    setState(() {
      _busy = true;
      _cancelSignal = signal;
      _progress = const CloudSyncProgress(
        phase: CloudSyncPhase.connecting,
        message: '准备同步…',
      );
    });
    try {
      await ref
          .read(cloudSyncStateStoreProvider)
          .saveCredential(baseUrl: _baseUrl.text, password: _password.text);
      final result = await ref
          .read(cloudSyncServiceProvider)
          .sync(mode: _mode, cancelSignal: signal, onProgress: _updateProgress);
      _handleSyncSuccess(messenger, result);
    } on AppError catch (error) {
      if (!mounted) return;
      ref.invalidate(appSettingsProvider);
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      _clearSyncBusy();
    }
  }

  void _updateProgress(CloudSyncProgress progress) {
    if (mounted) setState(() => _progress = progress);
  }

  void _handleSyncSuccess(
    ScaffoldMessengerState messenger,
    CloudSyncResult result,
  ) {
    if (!mounted) return;
    invalidateLocalData(ref);
    ref.invalidate(appSettingsProvider);
    final wire = result.transferredBytes > 0
        ? '（传输 ${formatBackupBytes(result.transferredBytes)}）'
        : '';
    messenger.showSnackBar(
      SnackBar(content: Text('${formatCloudSyncResultSummary(result)}$wire')),
    );
  }

  void _clearSyncBusy() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _cancelSignal = null;
    });
  }

  Future<bool> _confirmReplace() async {
    final confirmed = await showLexiConfirmSheet(
      context,
      title: '用 Next.js 云端数据覆盖本机？',
      body:
          '将分页拉取云端完整数据并整体替换本机全部词条、学习记录与词书包。'
          '本机当前数据不会保留且无法撤销（云端连接与凭据配置会自动保留）。',
      confirmLabel: '覆盖恢复',
      destructive: true,
      confirmButtonKey: cloudSyncReplaceConfirmButtonKey,
    );
    return confirmed;
  }

  static const List<ButtonSegment<CloudSyncMode>> _modeSegments =
      <ButtonSegment<CloudSyncMode>>[
        ButtonSegment<CloudSyncMode>(
          value: CloudSyncMode.bidirectional,
          label: Text('双向'),
          icon: Icon(LucideIcons.arrowLeftRight, size: 14),
        ),
        ButtonSegment<CloudSyncMode>(
          value: CloudSyncMode.pullMerge,
          label: Text('仅拉取'),
          icon: Icon(LucideIcons.cloudDownload, size: 14),
        ),
        ButtonSegment<CloudSyncMode>(
          value: CloudSyncMode.pullReplace,
          label: Text('覆盖'),
          icon: Icon(LucideIcons.replace, size: 14),
        ),
      ];

  String _modeHint(CloudSyncMode mode) => switch (mode) {
    CloudSyncMode.bidirectional => '双向：自动分片 GZip 双向增量合并，两边都保留全部词条与复习进度。',
    CloudSyncMode.pullMerge => '仅拉取：只把云端新变更并进本机，本机不删、也不修改云端数据。',
    CloudSyncMode.pullReplace => '覆盖：用云端数据整库替换本机，本机未同步数据将丢失且不可撤销。',
  };
}

class _CloudTextField extends StatelessWidget {
  const new({
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.secret,
  });

  final Key fieldKey;
  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ({bool obscure, VoidCallback onToggle})? secret;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final obscure = secret?.obscure ?? false;
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
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: !obscure,
          style: LexiType.body.copyWith(color: colors.label),
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            fillColor: colors.card,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s12,
              vertical: LexiSpace.s10,
            ),
            hintText: hint,
            hintStyle: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            suffixIcon: secret == null
                ? null
                : IconButton(
                    tooltip: obscure ? '显示密码' : '隐藏密码',
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: secret!.onToggle,
                    icon: Icon(obscure ? LucideIcons.eye : LucideIcons.eyeOff),
                  ),
          ),
        ),
      ],
    );
  }
}

class _CloudProgressBanner extends StatelessWidget {
  const new({required this.progress});

  final CloudSyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final wire = progress.transferredBytes > 0
        ? ' · ${formatBackupBytes(progress.transferredBytes)}'
        : '';
    return Surface(
      variant: SurfaceVariant.inset,
      padding: const EdgeInsets.all(LexiSpace.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${progress.message}$wire',
            key: const Key('cloudSyncProgressText'),
            style: LexiType.caption.copyWith(color: colors.label),
          ),
          if (progress.isActive) ...<Widget>[
            const SizedBox(height: LexiSpace.s6),
            LinearProgressIndicator(
              value: progress.fraction,
              minHeight: LexiSpace.s4,
              borderRadius: BorderRadius.circular(LexiRadius.xs),
            ),
          ],
        ],
      ),
    );
  }
}

class _CloudStatusLine extends StatelessWidget {
  const new({required this.settings, required this.configured});

  final CloudSyncSettings settings;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final status = settings.status;
    final lastError = status.lastError;
    final hasError = lastError != null && lastError.isNotEmpty;
    final lines = _buildLines(status, hasError: hasError);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < lines.length; i += 1)
          Padding(
            padding: const EdgeInsets.only(bottom: LexiSpace.s2),
            child: Row(
              children: <Widget>[
                Container(
                  width: _cloudStatusDotSize,
                  height: _cloudStatusDotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dotColor(
                      colors,
                      isError: hasError && i == lines.length - 1,
                    ),
                  ),
                ),
                const SizedBox(width: LexiSpace.s8),
                Expanded(
                  child: Text(
                    lines[i],
                    key: Key('cloudSyncStatus-$i'),
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
        if (configured)
          Padding(
            padding: const EdgeInsets.only(top: LexiSpace.s2),
            child: Text(
              '密码仅保存在本机数据库，导出备份或局域网同步时会自动剥离。',
              style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
            ),
          ),
      ],
    );
  }

  List<String> _buildLines(
    CloudSyncLastStatus status, {
    required bool hasError,
  }) => <String>[
    if (status.lastSuccessAt case final at?)
      '上次同步：${_formatTime(at)}'
          '${status.lastSummary == null ? '' : '（${status.lastSummary}）'}'
    else if (configured)
      '尚未同步过，首次双向同步会自动分页拉取与分批推送。'
    else
      '填写 Next.js 站点地址后即可跨端同步（密码与网页登录密码一致）。',
    if (hasError) '上次失败：${_errorLabel(status.lastError!)}',
  ];

  Color _dotColor(LexiColors colors, {required bool isError}) {
    if (isError) return colors.danger;
    if (settings.status.lastSuccessAt != null) return colors.success;
    return colors.borderStrong;
  }
}

String _errorLabel(String code) =>
    AppErrorCode.fromCode(code)?.defaultMessage ??
    AppErrorCode.cloudSyncRequestFailed.defaultMessage;

String _formatTime(int epochMs) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${pad(time.month)}-${pad(time.day)} '
      '${pad(time.hour)}:${pad(time.minute)}';
}
