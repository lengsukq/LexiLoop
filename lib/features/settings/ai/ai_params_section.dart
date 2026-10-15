/// AI 参数卡：启用开关、主/备用目标与采样参数。
///
/// **为什么不并进 provider 卡片**：一份 AI 配置供词条初始化、翻译、
/// 建议等全部功能共用（见 `llm_config.dart` 的说明），因此「用哪个
/// provider、哪个模型」必须独立于「provider 有哪些」存在——把它塞进某张
/// provider 卡片，等于宣称「AI 只能属于某一个 provider」，与三层降级
/// 的实现直接矛盾。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/features/settings/ai/bounded_number_field.dart';
import 'package:lexiloop/features/settings/ai/llm_settings_codec.dart';
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 推理强度的可选项；空串表示「交给模型自己决定」。
const List<String> reasoningEffortOptions = <String>[
  '',
  'minimal',
  'low',
  'medium',
  'high',
];

/// 数字字段的固定宽度：三个字段在手机上换行，在平板上并排。
const double _numericFieldWidth = 150;

/// AI 参数卡。
class AiParamsSection extends StatelessWidget {
  /// 以当前 LLM 配置与变更回调构造。
  const new({required this.config, required this.onChanged, super.key});

  /// 当前 LLM 配置。
  final LlmConfig config;

  /// 变更回调：参数卡只负责算出新配置，落库由外层统一做。
  final ValueChanged<LlmConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final ai = config.ai;
    return SettingsSectionCard(
      title: 'AI 参数',
      subtitle: '一份配置供词条初始化、翻译与建议共用；发音由系统 TTS 独立负责。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SettingsSwitchRow(
            switchKey: const Key('aiEnabledSwitch'),
            label: '启用 AI',
            description: '关闭后所有 AI 功能停止调用，已生成的内容不受影响。',
            value: ai.enabled,
            onChanged: (value) => onChanged(
              withAiFields(config, <String, Object?>{'enabled': value}),
            ),
          ),
          if (ai.enabled) ...<Widget>[
            const SizedBox(height: LexiSpace.s8),
            _TargetPickers(config: config, onChanged: onChanged),
            const SizedBox(height: LexiSpace.s8),
            _TuningFields(config: config, onChanged: onChanged),
            const SizedBox(height: LexiSpace.s8),
            _ThinkingFields(config: config, onChanged: onChanged),
            const SizedBox(height: LexiSpace.s8),
            _RetryFields(config: config, onChanged: onChanged),
          ],
        ],
      ),
    );
  }
}

/// 主 provider 与主模型。
class _TargetPickers extends StatelessWidget {
  const new({required this.config, required this.onChanged});

  final LlmConfig config;
  final ValueChanged<LlmConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final provider = config.primaryProvider;
    final models = provider == null
        ? const <String>[]
        : configuredModels(provider);
    final hint = config.providers.isEmpty ? '请先在上方添加 Provider' : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const Key('aiProviderSelect'),
            initialValue: _picked(
              config.providers.map((item) => item.id),
              config.ai.providerId,
            ),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '主 Provider',
              hintText: hint,
            ),
            items: <DropdownMenuItem<String>>[
              for (final item in config.providers)
                DropdownMenuItem<String>(
                  value: item.id,
                  child: Text(item.name.isEmpty ? item.id : item.name),
                ),
            ],
            onChanged: (value) {
              if (value != null) onChanged(withAiProvider(config, value));
            },
          ),
        ),
        const SizedBox(width: LexiSpace.s10),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const Key('aiModelSelect'),
            initialValue: _picked(models, config.ai.model),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '主模型',
              hintText: models.isEmpty ? '请先为该 Provider 添加模型' : null,
            ),
            items: <DropdownMenuItem<String>>[
              // 同理：`models` 非空但 `ai.model` 为空时需要这一项兜底。
              if (models.isNotEmpty)
                const DropdownMenuItem<String>(value: '', child: Text('未选择')),
              for (final model in models)
                DropdownMenuItem<String>(value: model, child: Text(model)),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged(
                  withAiFields(config, <String, Object?>{'model': value}),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

/// 温度、输出 token 上限与超时。
class _TuningFields extends StatelessWidget {
  const new({required this.config, required this.onChanged});

  final LlmConfig config;
  final ValueChanged<LlmConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final ai = config.ai;
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: <Widget>[
        _field(
          key: const Key('aiTemperature'),
          label: '温度',
          value: ai.temperature,
          bounds: (min: minLlmTemperature, max: maxLlmTemperature),
          onCommitted: (value) => onChanged(
            withAiFields(config, <String, Object?>{
              'temperature': value.toDouble(),
            }),
          ),
        ),
        _field(
          key: const Key('aiMaxOutputTokens'),
          label: '输出 Token 上限',
          value: ai.maxOutputTokens,
          bounds: (min: minLlmMaxOutputTokens, max: maxLlmMaxOutputTokens),
          onCommitted: (value) => onChanged(
            withAiFields(config, <String, Object?>{
              'maxOutputTokens': value.round(),
            }),
          ),
        ),
        _field(
          key: const Key('aiTimeoutSeconds'),
          label: '超时（秒）',
          value: ai.timeoutMs ~/ secondMs,
          bounds: (
            min: minLlmTimeoutMs ~/ secondMs,
            max: maxLlmTimeoutMs ~/ secondMs,
          ),
          onCommitted: (value) => onChanged(
            withAiFields(config, <String, Object?>{
              'timeoutMs': value.round() * secondMs,
            }),
          ),
        ),
      ],
    );
  }
}

/// 思考开关、思考预算与推理强度。
class _ThinkingFields extends StatelessWidget {
  const new({required this.config, required this.onChanged});

  final LlmConfig config;
  final ValueChanged<LlmConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final ai = config.ai;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsSwitchRow(
          switchKey: const Key('aiThinkingSwitch'),
          label: '启用思考',
          description: '推理模型会先想再答，耗时与费用显著增加。',
          value: ai.thinkingEnabled,
          onChanged: (value) => onChanged(
            withAiFields(config, <String, Object?>{'thinkingEnabled': value}),
          ),
        ),
        if (ai.thinkingEnabled)
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: <Widget>[
              _field(
                key: const Key('aiThinkingBudget'),
                label: '思考预算 Token',
                value: ai.thinkingBudgetTokens,
                bounds: (
                  min: minThinkingBudgetTokens,
                  max: maxThinkingBudgetTokens,
                ),
                onCommitted: (value) => onChanged(
                  withAiFields(config, <String, Object?>{
                    'thinkingBudgetTokens': value.round(),
                  }),
                ),
              ),
              SizedBox(
                width: _numericFieldWidth,
                child: DropdownButtonFormField<String>(
                  key: const Key('aiReasoningEffort'),
                  initialValue: _picked(
                    reasoningEffortOptions,
                    ai.reasoningEffort,
                  ),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '推理强度',
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final effort in reasoningEffortOptions)
                      DropdownMenuItem<String>(
                        value: effort,
                        child: Text(effort.isEmpty ? '自动' : effort),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      onChanged(
                        withAiFields(config, <String, Object?>{
                          'reasoningEffort': value,
                        }),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 备用 provider 与备用模型。
class _RetryFields extends StatelessWidget {
  const new({required this.config, required this.onChanged});

  final LlmConfig config;
  final ValueChanged<LlmConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _RetryHeader(),
        const SizedBox(height: LexiSpace.s6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _RetryProviderPicker(config: config, onChanged: onChanged),
            ),
            const SizedBox(width: LexiSpace.s10),
            Expanded(
              child: _RetryModelPicker(config: config, onChanged: onChanged),
            ),
          ],
        ),
      ],
    );
  }
}

/// 降级说明文案。
class _RetryHeader extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '失败降级',
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
        Text(
          '只对超时、限流、网络错误这类瞬时失败生效；鉴权失败重试没有意义。',
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
        ),
      ],
    );
  }
}

/// 备用 provider 下拉。
class _RetryProviderPicker extends StatelessWidget {
  const new({required this.config, required this.onChanged});

  final LlmConfig config;
  final ValueChanged<LlmConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <String>['', ...retryOptions(config)];
    return DropdownButtonFormField<String>(
      key: const Key('aiRetryProviderSelect'),
      initialValue: _picked(options, config.ai.retryProviderId),
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: '备用 Provider',
        isDense: true,
      ),
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem<String>(
          value: '',
          child: Text('与主 Provider 相同'),
        ),
        for (final id in retryOptions(config))
          DropdownMenuItem<String>(
            value: id,
            child: Text(_providerLabel(config, id)),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(withAiRetryProvider(config, value));
      },
    );
  }
}

/// 备用模型下拉。
class _RetryModelPicker extends StatelessWidget {
  const new({required this.config, required this.onChanged});

  final LlmConfig config;
  final ValueChanged<LlmConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final ai = config.ai;
    final retryProvider = ai.retryProviderId.isEmpty
        ? config.primaryProvider
        : config.providerById(ai.retryProviderId);
    final models = retryProvider == null
        ? const <String>[]
        : configuredModels(retryProvider);
    return DropdownButtonFormField<String>(
      key: const Key('aiRetryModelSelect'),
      initialValue: _picked(models, ai.retryModel),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '备用模型',
        isDense: true,
        hintText: models.isEmpty ? '与主模型相同' : null,
      ),
      items: <DropdownMenuItem<String>>[
        DropdownMenuItem<String>(
          value: '',
          child: Text(ai.retryProviderId.isEmpty ? '与主模型相同' : '自动选择'),
        ),
        for (final model in models)
          DropdownMenuItem<String>(value: model, child: Text(model)),
      ],
      onChanged: (value) {
        if (value != null) {
          onChanged(
            withAiFields(config, <String, Object?>{'retryModel': value}),
          );
        }
      },
    );
  }
}

/// 可选作备用 provider 的 ID（排除主 provider 自己）。
List<String> retryOptions(LlmConfig config) => <String>[
  for (final provider in config.providers)
    if (provider.id != config.ai.providerId) provider.id,
];

Widget _field({
  required Key key,
  required String label,
  required num value,
  required NumberBounds bounds,
  required ValueChanged<num> onCommitted,
}) => SizedBox(
  width: _numericFieldWidth,
  child: BoundedNumberField(
    key: key,
    label: label,
    value: value,
    bounds: bounds,
    onCommitted: onCommitted,
  ),
);

String _providerLabel(LlmConfig config, String providerId) {
  final provider = config.providerById(providerId);
  if (provider == null) return providerId;
  return provider.name.isEmpty ? provider.id : provider.name;
}

/// 下拉框的当前值：不在候选项里就回落到空。
///
/// 必须这么取：`ai.providerId` 可能指向一个已被手工删掉的 provider，
/// 直接把不存在的值塞给 `DropdownButtonFormField` 会触发断言。
String _picked(Iterable<String> options, String current) =>
    options.contains(current) ? current : '';
