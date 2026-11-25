/// 远程备份（WebDAV）设置分组。
///
/// 采用两列自适应紧凑表单与语义状态指示，让服务器凭据、自动备份周期与
/// 上传/测试/恢复操作紧凑有序地排在同一张卡片里。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_entry.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';
import 'package:lexiloop/features/settings/backup_size_label.dart';
import 'package:lexiloop/features/settings/data_invalidation.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';
import 'package:lexiloop/services/remote_backup/webdav_providers.dart';
import 'package:lexiloop/services/remote_backup/webdav_state_store.dart';
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

/// 远端恢复确认按钮的稳定 Key。
const Key restoreFromWebdavConfirmButtonKey = Key(
  'restoreFromWebdavConfirmButton',
);

/// 远端备份选择对话框的宽度（固定尺寸，不是间距——不参与 LexiSpace 音阶）。
const double webdavPickerWidth = 420;

/// 表单切分两列的宽度阈值。
const double _webdavTwoColBreakpoint = 440;

/// 卡片内操作按钮的紧凑高度。
const double _webdavButtonHeight = 38;

/// 状态点直径。
const double _webdavStatusDotSize = 7;

/// 远程备份分组。
class RemoteBackupSection extends ConsumerStatefulWidget {
  /// 创建远程备份分组。
  const new({super.key});

  @override
  ConsumerState<RemoteBackupSection> createState() =>
      _RemoteBackupSectionState();
}

class _RemoteBackupSectionState extends ConsumerState<RemoteBackupSection> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _directory;
  late final TextEditingController _username;
  late final TextEditingController _password;

  bool _busy = false;
  bool _seeded = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController();
    _directory = TextEditingController();
    _username = TextEditingController();
    _password = TextEditingController();
    ref.listenManual(appSettingsProvider, (previous, next) {
      final loaded = next.value;
      if (loaded == null || _seeded) return;
      _seed(loaded.raw[webdavSettingsKey]);
    }, fireImmediately: true);
  }

  void _seed(Object? raw) {
    _seeded = true;
    final credential = webdavSettingsFromRaw(raw).credential;
    _baseUrl.text = credential?.baseUrl ?? '';
    _directory.text = credential?.directory ?? '';
    _username.text = credential?.username ?? '';
    _password.text = credential?.password ?? '';
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _directory.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raw = ref.watch(appSettingsProvider).value?.raw[webdavSettingsKey];
    final settings = webdavSettingsFromRaw(raw);
    final configured = settings.isConfigured;

    return SectionCard(
      title: '远程备份（WebDAV）',
      icon: LucideIcons.cloud,
      tone: LexiTone.lavender,
      subtitle: '将备份传到坚果云、群晖或 Nextcloud，换机或本地丢失时随时取回。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Surface(
            variant: SurfaceVariant.inset,
            padding: const EdgeInsets.all(LexiSpace.s14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '服务器配置',
                      style: LexiType.body.copyWith(
                        color: context.lexiColors.label,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    LexiBadge(
                      label: configured ? '已配置' : '未配置',
                      tone: configured
                          ? LexiBadgeTone.success
                          : LexiBadgeTone.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: LexiSpace.s12),
                _credentialForm(),
                const SizedBox(height: LexiSpace.s10),
                _AutoIntervalField(
                  value: settings.state.autoIntervalMinutes,
                  onChanged: (minutes) => unawaited(
                    ref
                        .read<WebdavStateStore>(webdavStateStoreProvider)
                        .setAutoInterval(minutes),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: LexiSpace.s10),
          _StatusLine(state: settings.state, configured: configured),
          const SizedBox(height: LexiSpace.s12),
          _actionBar(configured: configured),
        ],
      ),
    );
  }

  Widget _credentialForm() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= _webdavTwoColBreakpoint;
      return Column(
        children: <Widget>[
          _fieldPair(
            wide: wide,
            firstFlex: 3,
            secondFlex: 2,
            first: _urlField(),
            second: _directoryField(),
          ),
          const SizedBox(height: LexiSpace.s8),
          _fieldPair(
            wide: wide,
            firstFlex: 1,
            secondFlex: 1,
            first: _usernameField(),
            second: _passwordField(),
          ),
        ],
      );
    },
  );

  Widget _fieldPair({
    required bool wide,
    required int firstFlex,
    required int secondFlex,
    required Widget first,
    required Widget second,
  }) => wide
      ? Row(
          children: <Widget>[
            Expanded(flex: firstFlex, child: first),
            const SizedBox(width: LexiSpace.s8),
            Expanded(flex: secondFlex, child: second),
          ],
        )
      : Column(
          children: <Widget>[
            first,
            const SizedBox(height: LexiSpace.s8),
            second,
          ],
        );

  Widget _urlField() => _WebdavField(
    fieldKey: const Key('webdavBaseUrlField'),
    label: '服务器地址',
    hint: 'https://dav.example.com/dav',
    controller: _baseUrl,
    onChanged: (value) => _saveCredential('baseUrl', value),
  );

  Widget _directoryField() => _WebdavField(
    fieldKey: const Key('webdavDirectoryField'),
    label: '备份目录',
    hint: '留空为根目录',
    controller: _directory,
    onChanged: (value) => _saveCredential('directory', value),
  );

  Widget _usernameField() => _WebdavField(
    fieldKey: const Key('webdavUsernameField'),
    label: '账号',
    hint: '登录用户名',
    controller: _username,
    onChanged: (value) => _saveCredential('username', value),
  );

  Widget _passwordField() => _WebdavField(
    fieldKey: const Key('webdavPasswordField'),
    label: '密码',
    hint: '应用专用密码',
    controller: _password,
    obscure: _obscurePassword,
    onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
    onChanged: (value) => _saveCredential('password', value),
  );

  Widget _actionBar({required bool configured}) {
    final colors = context.lexiColors;
    final compactText = LexiType.footnote.copyWith(fontWeight: FontWeight.w600);
    final outlineStyle = OutlinedButton.styleFrom(
      foregroundColor: colors.label,
      disabledForegroundColor: colors.tertiaryLabel,
      side: BorderSide(
        color: configured ? colors.borderDefault : colors.borderSubtle,
      ),
      minimumSize: const Size(0, _webdavButtonHeight),
      padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s14),
      textStyle: compactText,
    );
    return Wrap(
      spacing: LexiSpace.s8,
      runSpacing: LexiSpace.s8,
      children: <Widget>[
        FilledButton.icon(
          key: const Key('uploadToWebdav'),
          style: FilledButton.styleFrom(
            elevation: 0,
            minimumSize: const Size(0, _webdavButtonHeight),
            padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s14),
            textStyle: compactText,
          ),
          onPressed: _busy || !configured ? null : _uploadNow,
          icon: const Icon(LucideIcons.cloudUpload, size: 15),
          label: Text(_busy ? '处理中…' : '立即上传备份'),
        ),
        OutlinedButton.icon(
          key: const Key('testWebdavConnection'),
          style: outlineStyle,
          onPressed: _busy || !configured ? null : _testConnection,
          icon: const Icon(LucideIcons.plug, size: 15),
          label: const Text('测试连接'),
        ),
        OutlinedButton.icon(
          key: const Key('restoreFromWebdav'),
          style: outlineStyle,
          onPressed: _busy || !configured ? null : _restoreFromRemote,
          icon: const Icon(LucideIcons.cloudDownload, size: 15),
          label: const Text('从远端恢复'),
        ),
      ],
    );
  }

  WebdavSettings _currentSettings() {
    final raw = ref.read(appSettingsProvider).value;
    return webdavSettingsFromRaw(raw?.raw[webdavSettingsKey]);
  }

  Map<String, Object?> _rawWebdavMap() {
    final raw = ref.read(appSettingsProvider).value?.raw[webdavSettingsKey];
    if (raw is! Map) return <String, Object?>{};
    return <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  void _saveCredential(String key, String value) {
    final merged = <String, Object?>{..._rawWebdavMap(), key: value.trim()};
    if (key == 'baseUrl' && value.trim().isEmpty) {
      webdavCredentialFieldNames.forEach(merged.remove);
    }
    unawaited(_writeWebdav(merged));
  }

  Future<void> _writeWebdav(Map<String, Object?> value) => saveSettings(
    ref,
    <String, Object?>{webdavSettingsKey: value.isEmpty ? null : value},
  );

  Future<void> _testConnection() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final credential = _currentSettings().credential!;
      await ref
          .read(remoteBackupClientFactoryProvider)(credential)
          .ensureDirectory();
      messenger.showSnackBar(const SnackBar(content: Text('连接成功，备份目录可用。')));
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadNow() async {
    LexiHaptics.light();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref.read(webdavUploadServiceProvider).uploadNow();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '已上传 ${formatBackupBytes(result.byteSize)}'
            '（${result.totalRows} 行）：${result.fileName}',
          ),
        ),
      );
      _reloadStatus();
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      _reloadStatus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromRemote() async {
    final selected = await _pickRemoteBackup();
    if (selected == null || !mounted) return;
    if (!await _confirmRestore(selected) || !mounted) return;
    await _runRestore(selected);
  }

  Future<RemoteBackupEntry?> _pickRemoteBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    List<RemoteBackupEntry> entries;
    try {
      entries = await ref
          .read(webdavRestoreServiceProvider)
          .listRemoteBackups();
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return null;
    return await showDialog<RemoteBackupEntry>(
      context: context,
      builder: (dialogContext) => _RemoteBackupPicker(entries: entries),
    );
  }

  Future<bool> _confirmRestore(RemoteBackupEntry selected) =>
      showLexiConfirmSheet(
        context,
        title: '用远端备份覆盖本地？',
        body:
            '将下载 ${selected.name} 并整体替换本地全部词条、学习记录、'
            ' 导入历史与设置。当前数据不会保留，也无法撤销。\n\n'
            '建议先「立即上传备份」留个底。',
        confirmLabel: '覆盖恢复',
        destructive: true,
        confirmButtonKey: restoreFromWebdavConfirmButtonKey,
      );

  Future<void> _runRestore(RemoteBackupEntry selected) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(webdavRestoreServiceProvider)
          .restore(selected);
      if (!mounted) return;
      invalidateLocalData(ref);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '已从 ${selected.name} 恢复：'
            '${result.rowCounts['words'] ?? 0} 个词条、${result.totalRows} 行',
          ),
        ),
      );
      _seeded = false;
      _reloadStatus();
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reloadStatus() => ref.invalidate(appSettingsProvider);
}

class _WebdavField extends StatelessWidget {
  const new({
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.obscure = false,
    this.onToggleObscure,
  });

  final Key fieldKey;
  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool obscure;
  final VoidCallback? onToggleObscure;

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
            suffixIcon: onToggleObscure == null
                ? null
                : IconButton(
                    tooltip: obscure ? '显示密码' : '隐藏密码',
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: onToggleObscure,
                    icon: Icon(obscure ? LucideIcons.eye : LucideIcons.eyeOff),
                  ),
          ),
        ),
      ],
    );
  }
}

class _AutoIntervalField extends StatelessWidget {
  const new({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '自动备份周期',
          style: LexiType.caption.copyWith(
            color: colors.secondaryLabel,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: LexiSpace.s4),
        InputDecorator(
          decoration: InputDecoration(
            isDense: true,
            fillColor: colors.card,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s12,
              vertical: LexiSpace.s8,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              key: const Key('webdavAutoIntervalField'),
              value: value,
              isDense: true,
              isExpanded: true,
              style: LexiType.body.copyWith(color: colors.label),
              onChanged: (next) {
                if (next != null) onChanged(next);
              },
              items: <DropdownMenuItem<int>>[
                for (final minutes in webdavAutoIntervalOptions)
                  DropdownMenuItem<int>(
                    value: minutes,
                    child: Text(webdavAutoIntervalLabel(minutes)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 周期选项的展示文案。
String webdavAutoIntervalLabel(int minutes) {
  if (minutes <= 0) return '关闭（只手动上传）';
  if (minutes < 60) return '每 $minutes 分钟';
  if (minutes < 24 * 60) return '每 ${minutes ~/ 60} 小时';
  return '每 ${minutes ~/ (24 * 60)} 天';
}

class _StatusLine extends StatelessWidget {
  const new({required this.state, required this.configured});

  final WebdavBackupState state;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final lastError = state.lastError;
    final hasError = lastError != null && lastError.isNotEmpty;
    final lines = <String>[
      if (state.lastSuccessAt case final at?)
        '上次成功：${_formatTime(at)}'
      else if (configured)
        '还没有成功上传过'
      else
        '填齐地址、账号与密码后即可使用（多数服务需应用专用密码）。',
      if (hasError) '上次失败：${webdavErrorLabel(lastError)}',
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
                  width: _webdavStatusDotSize,
                  height: _webdavStatusDotSize,
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
                    key: Key('webdavStatus-$i'),
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
              '密码只保存在本机数据库里，不会随备份文件导出。',
              style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
            ),
          ),
      ],
    );
  }

  Color _dotColor(LexiColors colors, {required bool isError}) {
    if (isError) return colors.danger;
    if (state.lastSuccessAt != null) return colors.success;
    return colors.borderStrong;
  }
}

/// 错误码字符串对应的中文文案；未知码回落到通用失败文案。
String webdavErrorLabel(String code) =>
    AppErrorCode.fromCode(code)?.defaultMessage ??
    AppErrorCode.webdavRequestFailed.defaultMessage;

String _formatTime(int epochMs) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String pad(int value) =>
      value.toString().padLeft(2, '0'); // guard:allow-magic
  return '${time.year}-${pad(time.month)}-${pad(time.day)} '
      '${pad(time.hour)}:${pad(time.minute)}';
}

/// 列表里一项的副标题：大小 + 修改时间（服务器没给时间时只显示大小）。
String webdavEntrySubtitle(RemoteBackupEntry entry) {
  final size = formatBackupBytes(entry.sizeBytes);
  final modified = entry.modifiedAt;
  if (modified == null) return size;
  final time = _formatTime(modified.millisecondsSinceEpoch);
  return '$size · $time';
}

class _RemoteBackupPicker extends StatelessWidget {
  const new({required this.entries});

  final List<RemoteBackupEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return AlertDialog(
      title: const Text('选择要恢复的备份'),
      content: SizedBox(
        width: webdavPickerWidth,
        child: entries.isEmpty
            ? Text(
                AppErrorCode.webdavNoBackups.defaultMessage,
                key: const Key('webdavEmptyList'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return ListTile(
                    key: Key('webdavEntry-${entry.name}'),
                    title: Text(entry.name),
                    subtitle: Text(
                      webdavEntrySubtitle(entry),
                      style: LexiType.footnote.copyWith(
                        color: colors.secondaryLabel,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(entry),
                  );
                },
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
