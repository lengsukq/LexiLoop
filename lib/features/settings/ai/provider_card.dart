/// 单个 provider 的卡片。
///
/// **为什么要拆成「数据 + 操作」两个入参对象**：旧版 `ProviderCard` 收了
/// 13 个 props（见 `docs/CLEAN_CODE_BASELINE.md`）。这里把「这一张卡片
/// 展示什么」与「点按钮做什么」分成两组，父组件构造它们，卡片不再认识
/// 列表下标，也不需要知道配置怎么落库。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/features/settings/ai/ai_probe.dart';
import 'package:lexiloop/features/settings/ai/llm_settings_codec.dart';
import 'package:lexiloop/features/settings/ai/provider_editor_dialog.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 一次探测的进行中状态与结果。
class AiProbeState {
  /// 以进行中标记与（可选的）结果构造。
  const new({required this.busy, this.result});

  /// 是否正在请求。
  final bool busy;

  /// 上一次结果；为空表示还没跑过。
  final AiProbeResult? result;
}

/// 卡片展示的数据与两个写操作。
class AiProviderCardData {
  /// 以 provider、两组探测状态与编辑/删除回调构造。
  const new({
    required this.provider,
    required this.test,
    required this.models,
    required this.onEdit,
    required this.onRemove,
  });

  /// 这张卡片对应的 provider。
  final LlmProviderConfig provider;

  /// 「测试连接」的状态。
  final AiProbeState test;

  /// 「从 Models 接口获取」的状态。
  final AiProbeState models;

  /// 打开编辑对话框。
  final VoidCallback onEdit;

  /// 删除该 provider。
  final VoidCallback onRemove;
}

/// 卡片的联网与选择操作。
class AiProviderCardActions {
  /// 以五个回调构造。
  const new({
    required this.onTest,
    required this.onFetchModels,
    required this.onEditModels,
    required this.onRemoveModel,
    required this.onSelectDefaultModel,
  });

  /// 用默认模型发一次探测请求。
  final VoidCallback onTest;

  /// 拉取模型列表并打开选择器。
  final VoidCallback onFetchModels;

  /// 不联网，直接打开选择器管理已有模型。
  final VoidCallback onEditModels;

  /// 移除一个模型。
  final ValueChanged<String> onRemoveModel;

  /// 切换默认模型。
  final ValueChanged<String> onSelectDefaultModel;
}

/// provider 卡片。
class AiProviderCard extends StatelessWidget {
  /// 以数据与操作构造。
  const new({required this.data, required this.actions, super.key});

  /// 卡片数据。
  final AiProviderCardData data;

  /// 卡片操作。
  final AiProviderCardActions actions;

  @override
  Widget build(BuildContext context) {
    final provider = data.provider;
    return Padding(
      key: Key('aiProviderCard-${provider.id}'),
      padding: const EdgeInsets.only(bottom: LexiSpace.s10),
      child: _body(context, provider),
    );
  }

  Widget _body(BuildContext context, LlmProviderConfig provider) {
    final colors = context.lexiColors;
    return Material(
      color: colors.fill,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      child: Padding(
        padding: const EdgeInsets.all(LexiSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _header(context, provider),
            if (!provider.isUsable)
              Padding(
                padding: const EdgeInsets.only(top: LexiSpace.s6),
                child: Text(
                  '接口地址或 API Key 为空，该 Provider 目前不可用。',
                  style: LexiType.footnote.copyWith(color: colors.dangerText),
                ),
              ),
            const SizedBox(height: LexiSpace.s8),
            _defaultModel(context, provider),
            const SizedBox(height: LexiSpace.s8),
            _models(context, provider),
            _probeLine(
              context,
              state: data.models,
              key: Key('aiProviderModelsResult-${provider.id}'),
            ),
            _probeLine(
              context,
              state: data.test,
              key: Key('aiProviderTestResult-${provider.id}'),
            ),
            _buttons(provider),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, LlmProviderConfig provider) {
    final colors = context.lexiColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: _identity(context, provider)),
        IconButton(
          key: Key('aiProviderEdit-${provider.id}'),
          tooltip: '编辑',
          icon: Icon(
            LucideIcons.pencil,
            size: 18,
            color: colors.secondaryLabel,
          ),
          onPressed: data.onEdit,
        ),
        IconButton(
          key: Key('aiProviderRemove-${provider.id}'),
          tooltip: '删除',
          icon: Icon(LucideIcons.trash2, size: 18, color: colors.danger),
          onPressed: data.onRemove,
        ),
      ],
    );
  }

  /// 名称、ID、协议与接口地址。
  Widget _identity(BuildContext context, LlmProviderConfig provider) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          provider.name.isEmpty ? provider.id : provider.name,
          style: LexiType.callout.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '${provider.id} · ${apiTypeLabel(provider.apiType)}',
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
        ),
        if (provider.baseUrl.isNotEmpty)
          Text(
            provider.baseUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LexiType.caption.copyWith(color: colors.secondaryLabel),
          ),
      ],
    );
  }

  Widget _defaultModel(BuildContext context, LlmProviderConfig provider) {
    final models = configuredModels(provider);
    final colors = context.lexiColors;
    return DropdownButtonFormField<String>(
      key: Key('aiProviderDefaultModel-${provider.id}'),
      initialValue: models.contains(provider.defaultModel)
          ? provider.defaultModel
          : '',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '默认模型',
        isDense: true,
        hintText: models.isEmpty ? '请先获取或添加模型' : null,
        hintStyle: LexiType.body.copyWith(color: colors.tertiaryLabel),
      ),
      items: <DropdownMenuItem<String>>[
        // 必须有这一项：`models` 非空而 `defaultModel` 为空（备份里的旧配置
        // 就长这样）时，当前值是空串，没有对应项会触发下拉框断言。
        if (models.isNotEmpty)
          const DropdownMenuItem<String>(value: '', child: Text('未选择')),
        for (final model in models)
          DropdownMenuItem<String>(value: model, child: Text(model)),
      ],
      onChanged: (value) {
        if (value != null) actions.onSelectDefaultModel(value);
      },
    );
  }

  Widget _models(BuildContext context, LlmProviderConfig provider) {
    final colors = context.lexiColors;
    if (provider.models.isEmpty) {
      return Text(
        '还没有保存模型。',
        style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final model in provider.models)
          InputChip(
            key: Key('aiProviderModel-${provider.id}-$model'),
            label: Text(model, style: LexiType.footnote),
            deleteIcon: const Icon(LucideIcons.x, size: 14),
            onDeleted: () => actions.onRemoveModel(model),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _probeLine(
    BuildContext context, {
    required AiProbeState state,
    required Key key,
  }) {
    final result = state.result;
    if (result == null) return const SizedBox.shrink();
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(top: LexiSpace.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            result.success ? LucideIcons.circleCheck : LucideIcons.circleAlert,
            size: 15,
            color: result.success ? colors.success : colors.danger,
          ),
          const SizedBox(width: LexiSpace.s6),
          Expanded(
            child: Text(
              result.message,
              key: key,
              style: LexiType.footnote.copyWith(
                color: result.success ? colors.successDeep : colors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buttons(LlmProviderConfig provider) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        OutlinedButton.icon(
          key: Key('aiProviderTest-${provider.id}'),
          onPressed: data.test.busy ? null : actions.onTest,
          icon: data.test.busy
              ? _spinner()
              : const Icon(LucideIcons.zap, size: 16),
          label: Text(data.test.busy ? '测试中' : '测试连接'),
        ),
        OutlinedButton.icon(
          key: Key('aiProviderFetchModels-${provider.id}'),
          onPressed: data.models.busy ? null : actions.onFetchModels,
          icon: data.models.busy
              ? _spinner()
              : const Icon(LucideIcons.refreshCw, size: 16),
          label: Text(data.models.busy ? '读取中' : '从 Models 接口获取'),
        ),
        TextButton(
          key: Key('aiProviderManageModels-${provider.id}'),
          onPressed: actions.onEditModels,
          child: const Text('管理模型'),
        ),
      ],
    );
  }

  Widget _spinner() => const SizedBox(
    width: LexiSpace.s14,
    height: LexiSpace.s14,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
