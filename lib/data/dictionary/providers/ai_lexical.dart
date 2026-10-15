/// 把 LLM 包装成词典 provider。
///
/// 对应旧版 `modules/dictionary/providers/ai-lexical.ts`。
///
/// **与旧版的差异**：旧版自己实现了 HTTP 传输（`ai-lexical-transport.ts`
/// 后来退化为对 `callLlm` 的薄转发），本版直接复用 [LlmClient]，
/// 于是三层降级、结构化输出档位降级、超时与错误码映射只有一份实现。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/data/dictionary/providers/ai_lexical_content.dart';
import 'package:lexiloop/data/dictionary/providers/ai_lexical_schema.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/llm/llm_client.dart';
import 'package:lexiloop/services/llm/llm_config.dart';

/// AI 词条内容 provider。
class AiLexicalProvider implements DictionaryProvider {
  /// 以 LLM 客户端与 LLM 配置构造。
  const new(this._client, this._config);

  final LlmClient _client;
  final LlmConfig _config;

  /// 系统提示词：只要求返回一个合法 JSON 对象。
  static const String systemPrompt =
      'Return only one valid JSON object matching the requested schema.';

  @override
  String get id => 'ai:${_config.ai.providerId}:${_config.ai.model}';

  @override
  Set<String> get providedFields => providerCapabilities['ai']!;

  @override
  bool isEnabled(AppSettings settings) =>
      llmConfigFromSettings(settings.raw).isUsable;

  @override
  bool supports(ProviderRequest request) => true;

  @override
  Future<ProviderResult?> fetch(ProviderRequest request) async {
    final ai = _config.ai;
    _assertConfigured(ai);
    final output = await _generate(request, ai);
    _assertTerm(output, request.term);
    final issues = aiLexicalSemanticIssues(output, request);
    if (issues.isNotEmpty) {
      throw ExternalServiceError(
        AppErrorCode.aiSemanticInvalid,
        details: issues.join('；'),
      );
    }
    final score = aiLexicalQualityScore(output, request);
    if (score < aiQualityScoreThreshold) {
      throw ExternalServiceError(
        AppErrorCode.aiQualityLow,
        details: 'AI 内容质量评分过低：$score',
      );
    }
    final source = 'ai:${ai.providerId}:${ai.model}';
    return ProviderResult(
      fields: aiLexicalToFields(output, request, source),
      providerId: id,
      qualityScore: score > 100 ? 100 : score,
      metadata: <String, Object?>{
        'model': ai.model,
        'providerId': ai.providerId,
        'promptVersion': aiLexicalPromptVersion,
        'schemaVersion': aiLexicalSchemaVersion,
        'qualityScore': score,
      },
    );
  }

  void _assertConfigured(LlmAiConfig ai) {
    if (!ai.enabled) {
      throw const ExternalServiceError(
        AppErrorCode.aiDisabled,
        details: 'AI 词条初始化未启用',
      );
    }
    final provider = _config.providerById(ai.providerId);
    if (provider == null) {
      throw const ExternalServiceError(
        AppErrorCode.aiConfigIncomplete,
        details: 'AI Provider 未找到或已被删除',
      );
    }
    if (!provider.isUsable || ai.model.trim().isEmpty) {
      throw const ExternalServiceError(
        AppErrorCode.aiConfigIncomplete,
        details: 'AI 提供商、API Key、接口地址或模型未配置完整',
      );
    }
  }

  Future<Map<String, Object?>> _generate(
    ProviderRequest request,
    LlmAiConfig ai,
  ) async {
    final raw = await _client.completeJson(
      system: systemPrompt,
      user: aiLexicalPromptFor(request),
      schema: aiLexicalJsonSchema,
    );
    return normalizeAiLexicalOutput(raw);
  }

  void _assertTerm(Map<String, Object?> output, String term) {
    final returned = output['term'];
    final expected = term.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final actual = returned is String
        ? returned.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase()
        : '';
    if (actual != expected) {
      throw ExternalServiceError(
        AppErrorCode.aiTermMismatch,
        details: '模型返回了其他词条：$returned',
      );
    }
  }
}
