/// 「AI 模型」设置分组。
///
/// **这个 tab 为什么必须存在**：`AppSettings` 刻意不为 LLM 配置建模，
/// 原样保留在 `raw['llmConfig']`（见 `domain/models/app_settings.dart`）。
/// 于是「恢复旧备份」能带回一份可用的 AI 配置，用户却没有任何界面能改它——
/// 加不了 provider、改不了模型、连关掉 AI 都做不到，只能去动 SQLite。
/// 本分组是那份配置唯一的编辑入口。
///
/// **写回方式**：整块重写 [llmConfigSettingsKey]，而不是逐字段 merge。
/// 逐字段 merge 会留下一份「从哪来的都说不清」的 JSON；整块重写时由
/// [llmConfigToMap] 保证未知字段仍然存活。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/ai/ai_params_section.dart';
import 'package:lexiloop/features/settings/ai/ai_probe.dart';
import 'package:lexiloop/features/settings/ai/llm_settings_codec.dart';
import 'package:lexiloop/features/settings/ai/model_picker_dialog.dart';
import 'package:lexiloop/features/settings/ai/provider_card.dart';
import 'package:lexiloop/features/settings/ai/provider_editor_dialog.dart';
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 「AI 模型」分组。
class AiSettingsSection extends ConsumerStatefulWidget {
  /// 以当前设置构造。
  const new({required this.settings, super.key});

  /// 当前设置（LLM 配置从 [AppSettings.raw] 解析）。
  final AppSettings settings;

  @override
  ConsumerState<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends ConsumerState<AiSettingsSection> {
  /// 界面上的待写配置。
  ///
  /// 存在的原因：一次改动是「整块重写 `llmConfig`」，若连续改两个字段
  /// （例如先切 provider 再调温度），第二次必须基于第一次的结果合成，
  /// 否则后写的会把前一次覆盖掉。
  LlmConfig? _draft;

  /// 最近一次写出的配置形状，用来分辨「自己写进去了」与「被外部改写了」。
  String? _written;

  final Map<String, AiProbeState> _tests = <String, AiProbeState>{};
  final Map<String, AiProbeState> _modelResults = <String, AiProbeState>{};

  LlmConfig get _config => _draft ?? llmConfigFromSettings(widget.settings.raw);

  @override
  void didUpdateWidget(AiSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.raw[llmConfigSettingsKey] ==
        widget.settings.raw[llmConfigSettingsKey]) {
      return;
    }
    // 形状与刚写出的完全一致 → 自己的写入已落地，回到「以 raw 为准」；
    // 不一致说明是备份导入或恢复默认改的，外部值优先。
    if (_written != null && _encode(_config) == _written) {
      _draft = null;
      return;
    }
    _draft = null;
    _written = null;
    _tests.clear();
    _modelResults.clear();
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s4,
        LexiSpace.s12,
        LexiSpace.s4,
        LexiSpace.s24,
      ),
      children: <Widget>[
        _providersCard(context, config),
        const SizedBox(height: LexiSpace.s12),
        AiParamsSection(config: config, onChanged: _persist),
      ],
    );
  }

  Widget _providersCard(BuildContext context, LlmConfig config) {
    final colors = context.lexiColors;
    return SettingsSectionCard(
      title: '大模型 Provider',
      subtitle: '同一份配置供全部 AI 功能共用；API Key 只保存在本机数据库里。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('aiAddProvider'),
              onPressed: () => unawaited(_addProvider(config)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加 Provider'),
            ),
          ),
          const SizedBox(height: LexiSpace.s10),
          if (config.providers.isEmpty)
            Text(
              '暂无 Provider。添加一个并填好接口地址与 API Key 后才能启用 AI。',
              key: const Key('aiProviderEmptyHint'),
              style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
            ),
          for (final provider in config.providers)
            AiProviderCard(
              data: _cardData(provider),
              actions: _cardActions(provider),
            ),
        ],
      ),
    );
  }

  AiProviderCardData _cardData(LlmProviderConfig provider) =>
      AiProviderCardData(
        provider: provider,
        test: _tests[provider.id] ?? const AiProbeState(busy: false),
        models: _modelResults[provider.id] ?? const AiProbeState(busy: false),
        onEdit: () => unawaited(_editProvider(provider)),
        onRemove: () => unawaited(_removeProvider(provider)),
      );

  AiProviderCardActions _cardActions(LlmProviderConfig provider) =>
      AiProviderCardActions(
        onTest: () => unawaited(_testProvider(provider)),
        onFetchModels: () => unawaited(_fetchModels(provider)),
        onEditModels: () => unawaited(_manageModels(provider)),
        onRemoveModel: (model) => _removeModel(provider, model),
        onSelectDefaultModel: (model) =>
            _persist(withDefaultModel(_config, provider.id, model)),
      );

  /// 写入新的 LLM 配置。
  void _persist(LlmConfig next) {
    setState(() {
      _draft = next;
      _written = _encode(next);
    });
    unawaited(
      saveSettings(ref, <String, Object?>{
        llmConfigSettingsKey: llmConfigToMap(
          next,
          existing: widget.settings.raw[llmConfigSettingsKey],
        ),
      }),
    );
  }

  Future<void> _addProvider(LlmConfig config) async {
    final created = await showProviderEditor(
      context,
      takenIds: config.providers.map((item) => item.id).toSet(),
    );
    if (created == null || !mounted) return;
    _persist(withProvider(_config, created));
  }

  Future<void> _editProvider(LlmProviderConfig provider) async {
    final edited = await showProviderEditor(
      context,
      takenIds: <String>{provider.id},
      provider: provider,
    );
    if (edited == null || !mounted) return;
    final next = withProvider(_config, edited);
    _persist(
      edited.id == provider.id ? next : _retarget(next, provider.id, edited.id),
    );
  }

  Future<void> _removeProvider(LlmProviderConfig provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除 Provider'),
        content: Text(
          '确定删除「${provider.name.isEmpty ? provider.id : provider.name}」？'
          '它的 API Key 与模型列表会一并删除，且无法撤销。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('aiProviderRemoveConfirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _persist(removeProvider(_config, provider.id));
  }

  Future<void> _testProvider(LlmProviderConfig provider) async {
    final model = provider.defaultModel.isEmpty
        ? (provider.models.isEmpty ? '' : provider.models.first)
        : provider.defaultModel;
    setState(() => _tests[provider.id] = const AiProbeState(busy: true));
    final result = await probeProviderConnection(
      fetcher: ref.read(httpFetcherProvider),
      provider: provider,
      model: model,
    );
    if (!mounted) return;
    setState(
      () => _tests[provider.id] = AiProbeState(busy: false, result: result),
    );
  }

  Future<void> _fetchModels(LlmProviderConfig provider) async {
    final config = _config;
    setState(() => _modelResults[provider.id] = const AiProbeState(busy: true));
    try {
      final fetched = await fetchProviderModels(
        fetcher: ref.read(httpFetcherProvider),
        provider: provider,
        config: config,
      );
      if (!mounted) return;
      setState(
        () => _modelResults[provider.id] = AiProbeState(
          busy: false,
          result: AiProbeResult(success: true, message: fetched.message),
        ),
      );
      await _openPicker(provider, fetched.models);
    } on AiProbeFailure catch (failure) {
      if (!mounted) return;
      setState(
        () => _modelResults[provider.id] = AiProbeState(
          busy: false,
          result: AiProbeResult(success: false, message: failure.message),
        ),
      );
    }
  }

  /// 不联网地管理已有模型：模型被网关改名或下线时不必再拉一次接口。
  Future<void> _manageModels(LlmProviderConfig provider) =>
      _openPicker(provider, provider.models);

  Future<void> _openPicker(
    LlmProviderConfig provider,
    List<String> models,
  ) async {
    final selected = await showModelPicker(
      context,
      providerLabel: provider.name.isEmpty ? provider.id : provider.name,
      models: models,
      initialSelection: models.toSet(),
    );
    if (selected == null || !mounted) return;
    _persist(applyModels(_config, provider.id, selected));
  }

  /// 移除单个模型。
  ///
  /// **单键删除立即生效**，不走对话框：这是最常见的收尾动作（旧版要从
  /// Models 接口重新拉一遍才能删），再加一次确认只会让人多按两下。
  void _removeModel(LlmProviderConfig provider, String model) {
    _persist(removeModel(_config, provider.id, model));
  }

  /// provider 改 ID 时把 `ai` 里的引用一起搬过去。
  LlmConfig _retarget(LlmConfig config, String fromId, String toId) {
    final ai = config.ai;
    final fields = <String, Object?>{};
    if (ai.providerId == fromId) fields['providerId'] = toId;
    if (ai.retryProviderId == fromId) fields['retryProviderId'] = toId;
    return fields.isEmpty ? config : withAiFields(config, fields);
  }
}

String _encode(LlmConfig config) => jsonEncode(llmConfigToMap(config));
