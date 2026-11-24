/// LLM 配置的读写与引用修复。
///
/// **为什么不在界面里直接改 `settings.raw`**：`llmConfig` 的 JSON 形状由
/// `services/llm/llm_config.dart` 定义。界面层再抄一份结构，字段一改名
/// 就会出现「设置页写进去、解析层读不出来」的静默损坏。这里只做三件事：
/// 序列化（[llmConfigToMap]）、结构变更（[withProvider] 等）、
/// 以及结构变更后修复 `ai` 里指向已消失对象的引用（[reconcileAiModels]）。
///
/// **夹取不在这里做**：合法区间只由 `llm_config.dart` 决定，本文件通过
/// [llmConfigFromRaw] 复用它，而不是再抄一份 min/max。
library;

import 'package:lexiloop/services/llm/llm_config.dart';

/// 序列化 `llmConfig`，供写入 `settings.raw[llmConfig]`。
///
/// **为什么要传 [existing]**：`AppSettings` 的设计前提是「未建模的键原样
/// 写回」。`llmConfig` 里若出现本版本还不认识的键（例如旧版留下的小写
/// `apitype`），整块覆盖会让它永久消失。
Map<String, Object?> llmConfigToMap(LlmConfig config, {Object? existing}) {
  final base = <String, Object?>{};
  if (existing is Map) {
    for (final entry in existing.entries) {
      final key = entry.key;
      if (key is String) base[key] = entry.value;
    }
  }
  return <String, Object?>{
    ...base,
    'providers': providersToList(config.providers),
    'ai': aiToMap(config.ai),
  };
}

/// 序列化 provider 列表。
List<Object?> providersToList(List<LlmProviderConfig> providers) => <Object?>[
  for (final provider in providers) providerToMap(provider),
];

/// 序列化单个 provider。
Map<String, Object?> providerToMap(LlmProviderConfig provider) =>
    <String, Object?>{
      'id': provider.id,
      'name': provider.name,
      'apiType': provider.apiType.wire,
      'baseUrl': provider.baseUrl,
      'apiKey': provider.apiKey,
      'models': List<Object?>.of(provider.models),
      'defaultModel': provider.defaultModel,
    };

/// 序列化 `ai` 段。
///
/// **刻意不写 `retryCount`**：它在设置顶层（[aiRetryCountSettingsKey]），
/// 写进 `llmConfig.ai` 会被解析层静默忽略（旧版正是在这里踩过坑）。
Map<String, Object?> aiToMap(LlmAiConfig ai) => <String, Object?>{
  'enabled': ai.enabled,
  'providerId': ai.providerId,
  'model': ai.model,
  'retryProviderId': ai.retryProviderId,
  'retryModel': ai.retryModel,
  'temperature': ai.temperature,
  'maxOutputTokens': ai.maxOutputTokens,
  'timeoutMs': ai.timeoutMs,
  'thinkingEnabled': ai.thinkingEnabled,
  'thinkingBudgetTokens': ai.thinkingBudgetTokens,
  'reasoningEffort': ai.reasoningEffort,
  'features': ai.features.toJson(),
};

/// 切换 `ai.features` 中的单个用途开关。
LlmConfig withAiFeature(LlmConfig config, String key, {required bool value}) =>
    withAiFields(config, <String, Object?>{
      'features': <String, Object?>{...config.ai.features.toJson(), key: value},
    });

/// 替换整份 provider 列表。
LlmConfig withProviders(LlmConfig config, List<LlmProviderConfig> providers) =>
    llmConfigFromRaw(<String, Object?>{
      'providers': providersToList(providers),
      'ai': aiToMap(config.ai),
    });

/// 覆盖 `ai` 里的若干字段。
///
/// **为什么接收字段映射而不是逐个参数**：`LlmAiConfig` 有 11 个字段，
/// 写成 `withAiField(config, enabled: ..., model: ...)` 就是旧版那个
/// 13 + 8 回调 props 的同一个错误。改完存储形状再走一遍
/// [llmConfigFromRaw]，夹取规则仍然只有一份实现。
LlmConfig withAiFields(LlmConfig config, Map<String, Object?> fields) =>
    llmConfigFromRaw(<String, Object?>{
      'providers': providersToList(config.providers),
      'ai': <String, Object?>{...aiToMap(config.ai), ...fields},
    });

/// 新增或覆盖一个 provider（同 ID 视为同一个）。
LlmConfig withProvider(LlmConfig config, LlmProviderConfig provider) {
  final providers = <LlmProviderConfig>[...config.providers];
  final index = providers.indexWhere((item) => item.id == provider.id);
  if (index < 0) {
    providers.add(provider);
  } else {
    providers[index] = provider;
  }
  return withProviders(config, providers);
}

/// 删除一个 provider，并清空指向它的 `ai` 引用。
///
/// **为什么要一起改**：删除后界面上再没有任何入口能改 `ai.providerId`，
/// 用户会得到一份「看着配好了、实际永远不生效」的 AI，而且没有任何报错。
/// 与旧版一致：主 provider 被删时顺带关闭总开关，避免一个空配置一直在
/// 后台重试。
LlmConfig removeProvider(LlmConfig config, String providerId) {
  final next = withProviders(
    config,
    config.providers.where((item) => item.id != providerId).toList(),
  );
  final ai = config.ai;
  final fields = <String, Object?>{};
  if (ai.providerId == providerId) {
    fields['providerId'] = '';
    fields['enabled'] = false;
  }
  if (ai.retryProviderId == providerId) {
    fields['retryProviderId'] = '';
    fields['retryModel'] = '';
  }
  return fields.isEmpty ? next : withAiFields(next, fields);
}

/// 用选择结果整体替换某个 provider 的模型列表。
///
/// 旧版是「并集」语义，因此勾掉一个已有模型不会生效，用户只能删除整个
/// provider 重配。这里改成「选择结果即最终列表」，模型被删掉时
/// [reconcileAiModels] 会顺带修好 `ai.model`。
LlmConfig applyModels(
  LlmConfig config,
  String providerId,
  List<String> selection,
) {
  final provider = config.providerById(providerId);
  if (provider == null) return config;
  final models = dedupeModels(selection);
  // 原来的 defaultModel 不在选择结果里时改用第一个，模型被清空则留空。
  final defaultModel = models.contains(provider.defaultModel)
      ? provider.defaultModel
      : (models.isEmpty ? '' : models.first);
  return _replaceModels(config, providerId, models, defaultModel);
}

/// 移除单个模型（卡片上的标签删除按钮）。
LlmConfig removeModel(LlmConfig config, String providerId, String model) {
  final provider = config.providerById(providerId);
  if (provider == null) return config;
  final models = provider.models.where((item) => item != model).toList();
  final defaultModel = provider.defaultModel == model
      ? (models.isEmpty ? '' : models.first)
      : provider.defaultModel;
  return _replaceModels(config, providerId, models, defaultModel);
}

LlmConfig _replaceModels(
  LlmConfig config,
  String providerId,
  List<String> models,
  String defaultModel,
) {
  final providers = <LlmProviderConfig>[
    for (final provider in config.providers)
      if (provider.id == providerId)
        LlmProviderConfig(
          id: provider.id,
          name: provider.name,
          apiType: provider.apiType,
          baseUrl: provider.baseUrl,
          apiKey: provider.apiKey,
          models: models,
          defaultModel: defaultModel,
        )
      else
        provider,
  ];
  return reconcileAiModels(withProviders(config, providers));
}

/// 设置某个 provider 的默认模型。
///
/// 改完要让 `ai` 里的引用重新对齐：默认模型变了之后，原本指向「第一个模型」
/// 的 `ai.model` 会变成另一个模型，用户会以为模型被偷偷换了。
LlmConfig withDefaultModel(LlmConfig config, String providerId, String model) =>
    reconcileAiModels(
      withProviders(config, <LlmProviderConfig>[
        for (final provider in config.providers)
          if (provider.id == providerId)
            LlmProviderConfig(
              id: provider.id,
              name: provider.name,
              apiType: provider.apiType,
              baseUrl: provider.baseUrl,
              apiKey: provider.apiKey,
              models: provider.models,
              defaultModel: model,
            )
          else
            provider,
      ]),
    );

/// 让 `ai.model` / `ai.retryModel` 重新指向仍然存在的模型。
///
/// **为什么必须修**：模型被删掉后 `ai.model` 会指向一个不存在的模型，
/// 每次 AI 调用都会 404，而界面上看不出任何异常——用户只会认为「AI 坏了」。
LlmConfig reconcileAiModels(LlmConfig config) {
  final ai = config.ai;
  final retryProviderId =
      ai.retryProviderId.isEmpty ||
          config.providerById(ai.retryProviderId) != null
      ? ai.retryProviderId
      : '';
  final retryProvider = retryProviderId.isEmpty
      ? config.primaryProvider
      : config.providerById(retryProviderId);
  final model = _keptModel(config.providerById(ai.providerId), ai.model);
  final retryModel = _keptModel(retryProvider, ai.retryModel);
  if (model == ai.model &&
      retryModel == ai.retryModel &&
      retryProviderId == ai.retryProviderId) {
    return config;
  }
  return withAiFields(config, <String, Object?>{
    'model': model,
    'retryModel': retryModel,
    'retryProviderId': retryProviderId,
  });
}

/// 切换主 provider，并把模型收敛到该 provider 的首选模型。
///
/// 换 provider 后原模型多半不存在，留在配置里只会让用户看到「已配置」
/// 却始终失败。
LlmConfig withAiProvider(LlmConfig config, String providerId) =>
    withAiFields(config, <String, Object?>{
      'providerId': providerId,
      'model': preferredModel(config.providerById(providerId)),
    });

/// 切换备用 provider；传空串表示「与主 provider 相同」。
LlmConfig withAiRetryProvider(LlmConfig config, String retryProviderId) {
  final provider = retryProviderId.isEmpty
      ? config.primaryProvider
      : config.providerById(retryProviderId);
  return withAiFields(config, <String, Object?>{
    'retryProviderId': retryProviderId,
    'retryModel': preferredModel(provider),
  });
}

/// provider 的可选模型：`models` 与 `defaultModel` 的并集。
///
/// 与旧版 `settings-shared.ts` 的 `configuredModels` 同义。
List<String> configuredModels(LlmProviderConfig provider) {
  final result = <String>[];
  for (final model in <String>[...provider.models, provider.defaultModel]) {
    if (model.isNotEmpty && !result.contains(model)) result.add(model);
  }
  return result;
}

/// provider 的首选模型：`defaultModel`，没有则取第一个。
String preferredModel(LlmProviderConfig? provider) {
  if (provider == null) return '';
  if (provider.defaultModel.isNotEmpty) return provider.defaultModel;
  return provider.models.isEmpty ? '' : provider.models.first;
}

/// 去空白、去重、丢弃空串。
List<String> dedupeModels(Iterable<String> values) {
  final result = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || result.contains(trimmed)) continue;
    result.add(trimmed);
  }
  return result;
}

String _keptModel(LlmProviderConfig? provider, String current) {
  if (provider == null) return '';
  if (configuredModels(provider).contains(current)) return current;
  return preferredModel(provider);
}
