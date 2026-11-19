/// 远程备份（WebDAV）设置分组。
///
/// **为什么作为一个独立分组而不是塞进「备份与导入」**：本地导入导出是
/// 一次性动作，远程备份是有配置、有周期、有状态的持续功能。混在一张卡片里
/// 会让「导出备份」这个简单动作旁边堆着地址、账号、密码、周期四行输入。
///
/// **密码为什么要提示「应用专用密码」**：坚果云、群晖这类服务对第三方客户端
/// 强制要求单独生成的密码，直接填登录密码必然 401。文案在错误提示里点明，
/// 比放在文档里更容易被看到。
///
/// **自动备份的状态为什么在界面上**：它是后台行为，用户看不到过程；
/// 只给一个开关的话，「到底传没传上去」永远是个疑问。
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
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/lexi_confirm_sheet.dart';
import 'package:lexiloop/ui/widgets/lexi_form_rows.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 远端恢复确认按钮的稳定 Key。
const Key restoreFromWebdavConfirmButtonKey = Key(
  'restoreFromWebdavConfirmButton',
);

/// 远端备份选择对话框的宽度（固定尺寸，不是间距——不参与 LexiSpace 音阶）。
const double webdavPickerWidth = 420;

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

  @override
  void initState() {
    super.initState();
    // `appSettingsProvider` 是异步的：首帧时设置往往还没读出来。
    // 这里先建空控制器，等设置真的到了再灌一次初值——
    // 否则「打开设置页 → 直接点测试连接」会用上一份空凭据。
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

  /// 把库里已有的配置灌进输入框。
  ///
  /// 只在「首次读到设置」与「恢复备份之后」两处调用，因此不会覆盖用户
  /// 正在输入的内容；库里没有凭据时把四个框清空（恢复备份会把密码剥掉）。
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
    // **必须 watch**：设置是异步读出来的，只 `read` 的话首帧拿到的永远是
    // 「未配置」，按钮会一直灰着，直到窗口因别的原因重建。
    final raw = ref.watch(appSettingsProvider).value?.raw[webdavSettingsKey];
    final settings = webdavSettingsFromRaw(raw);

    return SettingsSectionCard(
      title: '远程备份（WebDAV）',
      subtitle:
          '把同一份 JSON 备份传到自建的 WebDAV（坚果云 / 群晖 / Nextcloud 等），'
          ' 换机或本地数据丢失时可以取回。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ..._credentialFields(),
          const SizedBox(height: LexiSpace.s12),
          _AutoIntervalRow(
            value: settings.state.autoIntervalMinutes,
            onChanged: (minutes) => unawaited(
              ref
                  .read<WebdavStateStore>(webdavStateStoreProvider)
                  .setAutoInterval(minutes),
            ),
          ),
          const SizedBox(height: LexiSpace.s12),
          _StatusLine(state: settings.state),
          const SizedBox(height: LexiSpace.s12),
          ..._actionButtons(configured: settings.isConfigured),
        ],
      ),
    );
  }

  /// 四个凭据输入行。
  List<Widget> _credentialFields() => <Widget>[
    _TextRow(
      fieldKey: const Key('webdavBaseUrlField'),
      label: '服务器地址',
      hint: 'https://dav.example.com/dav',
      controller: _baseUrl,
      onChanged: (value) => _saveCredential('baseUrl', value),
    ),
    const SizedBox(height: LexiSpace.s8),
    _TextRow(
      fieldKey: const Key('webdavDirectoryField'),
      label: '备份目录',
      hint: '留空表示服务器根目录',
      controller: _directory,
      onChanged: (value) => _saveCredential('directory', value),
    ),
    const SizedBox(height: LexiSpace.s8),
    _TextRow(
      fieldKey: const Key('webdavUsernameField'),
      label: '账号',
      hint: '登录用户名',
      controller: _username,
      onChanged: (value) => _saveCredential('username', value),
    ),
    const SizedBox(height: LexiSpace.s8),
    _TextRow(
      fieldKey: const Key('webdavPasswordField'),
      label: '密码',
      hint: '多数服务需要「应用专用密码」，而不是登录密码',
      controller: _password,
      obscure: true,
      onChanged: (value) => _saveCredential('password', value),
    ),
  ];

  /// 三个动作按钮与下方的说明文案。
  List<Widget> _actionButtons({required bool configured}) {
    final colors = context.lexiColors;
    return <Widget>[
      OutlinedButton.icon(
        key: const Key('testWebdavConnection'),
        onPressed: _busy || !configured ? null : _testConnection,
        icon: const Icon(LucideIcons.wifi, size: 16),
        label: const Text('测试连接'),
      ),
      const SizedBox(height: LexiSpace.s8),
      FilledButton.icon(
        key: const Key('uploadToWebdav'),
        onPressed: _busy || !configured ? null : _uploadNow,
        icon: const Icon(LucideIcons.cloudUpload, size: 16),
        label: Text(_busy ? '处理中…' : '立即上传一份备份'),
      ),
      const SizedBox(height: LexiSpace.s8),
      OutlinedButton.icon(
        key: const Key('restoreFromWebdav'),
        onPressed: _busy || !configured ? null : _restoreFromRemote,
        icon: const Icon(LucideIcons.cloudDownload, size: 16),
        label: const Text('从远端恢复（覆盖本地）'),
      ),
      const SizedBox(height: LexiSpace.s8),
      Text(
        configured
            ? '密码只保存在本机数据库里，不会上传到任何服务器；'
                  '导出的备份文件里也不含它。'
            : '填齐地址、账号与密码后即可使用。',
        style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
      ),
    ];
  }

  /// 当前设置（未加载出来时用默认值）。
  WebdavSettings _currentSettings() {
    final raw = ref.read(appSettingsProvider).value;
    return webdavSettingsFromRaw(raw?.raw[webdavSettingsKey]);
  }

  /// 存储里的原始映射（**不做**「凭据是否完整」的判定）。
  ///
  /// 必须以原始映射为合并基准，而不是解析后的 `WebdavCredential`：
  /// 用户在地址栏敲到一半时密码往往还是空的，此时凭据解析结果为 `null`，
  /// 拿它当基准会把已经填好的地址与账号一起抹掉。
  Map<String, Object?> _rawWebdavMap() {
    final raw = ref.read(appSettingsProvider).value?.raw[webdavSettingsKey];
    if (raw is! Map) return <String, Object?>{};
    return <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  /// 写入凭据里的一个字段。
  ///
  /// 四个字段分开写：用户改地址时，账号与密码必须原样保留。
  void _saveCredential(String key, String value) {
    final merged = <String, Object?>{..._rawWebdavMap(), key: value.trim()};
    if (key == 'baseUrl' && value.trim().isEmpty) {
      // 地址没了就没有可连的服务器，但**只清凭据**：自动备份周期与
      // 「上次成功」属于状态，不该因为改了地址而一起丢掉。
      webdavCredentialFieldNames.forEach(merged.remove);
    }
    unawaited(_writeWebdav(merged));
  }

  /// 把一份新的 `webdavBackup` 值写回设置。
  ///
  /// 只传 `credentials` 时状态字段由调用方从原始映射带出；
  /// 传空映射表示把整个键清空。
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

  /// 「从远端恢复」的完整流程：列目录 → 选一份 → 底部确认 → 下载并导入。
  Future<void> _restoreFromRemote() async {
    final selected = await _pickRemoteBackup();
    if (selected == null || !mounted) return;
    if (!await _confirmRestore(selected) || !mounted) return;
    await _runRestore(selected);
  }

  /// 列出远端备份并让用户选一份；失败或取消时返回 `null`。
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

  /// 恢复前的确认：明说这是不可撤销的整库替换。
  Future<bool> _confirmRestore(RemoteBackupEntry selected) =>
      showLexiConfirmSheet(
        context,
        title: '用远端备份覆盖本地？',
        body:
            '将下载 ${selected.name} 并整体替换本地全部词条、学习记录、'
            ' 导入历史与设置。当前数据不会保留，也无法撤销。\n\n'
            '建议先「立即上传一份备份」留个底。',
        confirmLabel: '覆盖恢复',
        destructive: true,
        confirmButtonKey: restoreFromWebdavConfirmButtonKey,
      );

  /// 真正执行恢复；成功后失效全部读库缓存。
  Future<void> _runRestore(RemoteBackupEntry selected) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(webdavRestoreServiceProvider)
          .restore(selected);
      if (!mounted) return;
      // 与本地导入同一条约定：恢复是原地替换，必须显式失效缓存。
      invalidateLocalData(ref);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '已从 ${selected.name} 恢复：'
            '${result.rowCounts['words'] ?? 0} 个词条、${result.totalRows} 行',
          ),
        ),
      );
      // 恢复会整体替换设置表，远端配置要按恢复后的内容重新灌一次：
      // 备份里的密码已被剥掉，输入框不能继续显示恢复前那个。
      _seeded = false;
      _reloadStatus();
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 备份状态写在设置表里，界面靠重建 provider 读回最新值。
  void _reloadStatus() => ref.invalidate(appSettingsProvider);
}

/// 普通文本输入行。
class _TextRow extends StatelessWidget {
  const new({
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.obscure = false,
  });

  final Key fieldKey;
  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// 是否隐藏输入（密码）。
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return TextField(
      key: fieldKey,
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: LexiType.body.copyWith(color: colors.tertiaryLabel),
      ),
    );
  }
}

/// 自动备份周期的选择行。
class _AutoIntervalRow extends StatelessWidget {
  const new({required this.value, required this.onChanged});

  /// 当前周期（分钟）；`0` 表示关闭。
  final int value;

  /// 变更回调。
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('自动备份', style: LexiType.body.copyWith(color: colors.label)),
        const SizedBox(height: LexiSpace.s6),
        DropdownButton<int>(
          key: const Key('webdavAutoIntervalField'),
          value: value,
          isExpanded: true,
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

/// 状态行：上次成功、上次失败、数据是否已变化。
class _StatusLine extends StatelessWidget {
  const new({required this.state});

  final WebdavBackupState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final lastError = state.lastError;
    final lines = <String>[
      if (state.lastSuccessAt case final at?)
        '上次成功：${_formatTime(at)}'
      else
        '还没有成功上传过。',
      if (lastError != null && lastError.isNotEmpty)
        '上次失败：${webdavErrorLabel(lastError)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: LexiSpace.s2),
            child: Text(
              line,
              key: Key('webdavStatus-${lines.indexOf(line)}'),
              style: LexiType.footnote.copyWith(
                color: lastError != null && line == lines.last
                    ? colors.danger
                    : colors.secondaryLabel,
              ),
            ),
          ),
      ],
    );
  }
}

/// 错误码字符串对应的中文文案；未知码回落到通用失败文案。
String webdavErrorLabel(String code) =>
    AppErrorCode.fromCode(code)?.defaultMessage ??
    AppErrorCode.webdavRequestFailed.defaultMessage;

/// 把时间戳写成 `2026-10-16 10:15`。
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

/// 远端备份选择对话框。
///
/// 空列表时给出明确的「远端没有备份」而不是一个空白对话框。
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
