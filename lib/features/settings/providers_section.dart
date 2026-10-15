/// 数据源设置分组。
///
/// 5 个数据源开关 + Merriam-Webster 的两个 API Key。
///
/// **为什么 MW Key 走 `raw`**：`AppSettings` 没有为它建模（AI provider 配置
/// 也尚未建模），键值原样保留在 `raw` 里。直接 `settingsService.update`
/// 写入即可，读回时用 `settings.raw['merriamWebsterDictionaryKey']`。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/import/provider_targets.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// Merriam-Webster 词典 API Key 的存储键。
const String merriamWebsterDictionaryKeyName = 'merriamWebsterDictionaryKey';

/// Merriam-Webster 同义词词典 API Key 的存储键。
const String merriamWebsterThesaurusKeyName = 'merriamWebsterThesaurusKey';

/// 数据源开关的 Key（用数据源 id 拼，避免界面与数据层的 id 各写一份）。
Key providerSwitchKey(String providerId) => Key('providerSwitch-$providerId');

/// 数据源分组。
class ProvidersSection extends ConsumerStatefulWidget {
  /// 以当前设置构造。
  const new({required this.settings, super.key});

  /// 当前设置。
  final AppSettings settings;

  @override
  ConsumerState<ProvidersSection> createState() => _ProvidersSectionState();
}

class _ProvidersSectionState extends ConsumerState<ProvidersSection> {
  late final TextEditingController _dictionaryKey = TextEditingController(
    text: _rawValue(merriamWebsterDictionaryKeyName),
  );
  late final TextEditingController _thesaurusKey = TextEditingController(
    text: _rawValue(merriamWebsterThesaurusKeyName),
  );

  @override
  void dispose() {
    _dictionaryKey.dispose();
    _thesaurusKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providers = widget.settings.providers;
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
      children: <Widget>[
        SettingsSectionCard(
          title: '词典与翻译数据源',
          subtitle: '初始化词条时按启用顺序调用；全部关闭则只能用 CSV 自带的内容。',
          child: Column(
            children: <Widget>[
              SettingsSwitchRow(
                switchKey: providerSwitchKey(providerYoudao),
                label: '有道',
                value: providers.youdaoEnabled,
                onChanged: (value) => _save('youdaoEnabled', value),
              ),
              SettingsSwitchRow(
                switchKey: providerSwitchKey(providerIciba),
                label: '爱词霸',
                value: providers.icibaEnabled,
                onChanged: (value) => _save('icibaEnabled', value),
              ),
              SettingsSwitchRow(
                switchKey: providerSwitchKey(providerDictionaryApi),
                label: 'dictionaryapi.dev',
                description: '免费英文词典，提供音标与例句。',
                value: providers.dictionaryApiEnabled,
                onChanged: (value) => _save('dictionaryApiEnabled', value),
              ),
              SettingsSwitchRow(
                switchKey: providerSwitchKey(providerMyMemory),
                label: 'MyMemory 翻译',
                value: providers.myMemoryEnabled,
                onChanged: (value) => _save('myMemoryEnabled', value),
              ),
              SettingsSwitchRow(
                switchKey: providerSwitchKey(providerMerriamWebster),
                label: 'Merriam-Webster',
                description: '需要 API Key；免费额度为每天 1000 次。',
                value: providers.merriamWebsterEnabled,
                onChanged: (value) => _save('merriamWebsterEnabled', value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SettingsSectionCard(
          title: 'Merriam-Webster API Key',
          subtitle: '只保存在本机数据库里，不会上传到任何服务器。',
          child: Column(
            children: <Widget>[
              _SecretField(
                fieldKey: const Key('merriamWebsterDictionaryKeyField'),
                label: '词典 API Key',
                controller: _dictionaryKey,
                onChanged: (value) =>
                    _saveRaw(merriamWebsterDictionaryKeyName, value),
              ),
              const SizedBox(height: 8),
              _SecretField(
                fieldKey: const Key('merriamWebsterThesaurusKeyField'),
                label: '同义词词典 API Key',
                controller: _thesaurusKey,
                onChanged: (value) =>
                    _saveRaw(merriamWebsterThesaurusKeyName, value),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 读取 `raw` 里的未建模键。
  String _rawValue(String key) {
    final value = widget.settings.raw[key];
    return value is String ? value : '';
  }

  void _save(String key, Object? value) {
    unawaited(saveSettings(ref, <String, Object?>{key: value}));
  }

  /// 未建模的键：空串表示「删除该键」，而不是存一个空字符串。
  void _saveRaw(String key, String value) {
    unawaited(
      saveSettings(ref, <String, Object?>{key: value.isEmpty ? null : value}),
    );
  }
}

/// 带隐藏显示的密钥输入框。
class _SecretField extends StatelessWidget {
  const new({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return TextField(
      key: fieldKey,
      controller: controller,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: '留空表示不使用',
        hintStyle: TextStyle(color: colors.tertiaryLabel, fontSize: 13),
      ),
    );
  }
}
