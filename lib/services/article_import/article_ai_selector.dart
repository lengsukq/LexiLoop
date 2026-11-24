/// 文章导入的 AI 选词调用。
///
/// 对应旧版 `src/modules/article-import/ai-select.ts`（99 行）。
///
/// **为什么在这里而不是 `domain/`**：架构守卫要求「LLM 调用只能出现在
/// service 层」，`LlmClient` 依赖 `HttpFetcher`（dio），domain 必须保持纯 Dart。
/// 因此 domain 只负责提示词与结构解析，真正的网络请求留在这里。
///
/// **失败一律转成结果而不是异常**：旧版 `aiSelectTerms` 把失败原因塞进
/// `AiSelectResult.error`，调用方继续走本地回退。保持这个形状，
/// 调用点就不会出现「catch 之后返回空候选」这种把 AI 故障伪装成
/// 「没有值得学的词」的写法。
library;

import 'dart:math' as math;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/domain/article_import/article_ai_models.dart';
import 'package:lexiloop/domain/article_import/article_ai_schema.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/domain/article_import/article_prompt.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/llm/llm_client.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/services/llm/llm_json.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 一次 AI 选词的输入。
class ArticleAiSelectInput {
  /// 以各字段构造。
  const new({
    required this.articleText,
    required this.candidates,
    required this.knownSample,
    required this.totalKnown,
    this.examTargets = const <VocabularyLevel>[],
    this.difficultyMode = ArticleDifficultyMode.atOrAbove,
    this.extractScope = ArticleExtractScope.wordsOnly,
  });

  /// 文章正文（含句子片段）。
  final String articleText;

  /// 送进提示词的候选。
  final List<ArticlePromptCandidate> candidates;

  /// 已掌握词样本。
  final List<String> knownSample;

  /// 已掌握词总数。
  final int totalKnown;

  /// 考试目标。
  final List<VocabularyLevel> examTargets;

  /// 难度筛选模式。
  final ArticleDifficultyMode difficultyMode;

  /// 提取范围。
  final ArticleExtractScope extractScope;
}

/// AI 选词器。
///
/// 抽成接口是为了让服务层测试可以注入假选词器，**不发真实网络请求**。
abstract interface class ArticleAiSelector {
  /// 发起一次选词；失败时返回带原因的失败结果，不抛异常。
  Future<ArticleAiSelection> select(ArticleAiSelectInput input);
}

/// 按当前设置解析 LLM 配置后再请求的选词器。
///
/// 「AI 未启用」与「配置不完整」要给出**不同**的提示：前者用户去开启即可，
/// 后者要回设置页补 Key / 模型。旧版 `ai-select.ts` 就是分开判断的。
class SettingsArticleAiSelector implements ArticleAiSelector {
  /// 以设置服务与 HTTP 客户端构造。
  const new(this._settings, this._fetcher);

  final SettingsService _settings;
  final HttpFetcher _fetcher;

  @override
  Future<ArticleAiSelection> select(ArticleAiSelectInput input) async {
    final settings = await _settings.load();
    final config = llmConfigFromSettings(settings.raw);
    if (!config.ai.enabled) {
      return const ArticleAiSelection.failure(
        errorCode: AppErrorCode.aiDisabled,
        error: 'AI 未启用，请到「设置 → AI 模型」开启 AI。',
      );
    }
    if (!config.ai.features.articleTokenize) {
      return const ArticleAiSelection.failure(
        errorCode: AppErrorCode.aiDisabled,
        error: '文章智能分词开关已关闭，请到「设置 → AI 模型」开启。',
      );
    }
    if (!config.isUsable) {
      return const ArticleAiSelection.failure(
        errorCode: AppErrorCode.aiConfigIncomplete,
        error: 'AI 服务配置不完整，请到「设置 → AI 模型」补全。',
      );
    }
    return await LlmArticleAiSelector(_fetcher, config).select(input);
  }
}

/// 用 [LlmClient] 发起一次结构化请求的选词器。
class LlmArticleAiSelector implements ArticleAiSelector {
  /// 以 HTTP 客户端与已解析的 LLM 配置构造。
  const new(this._fetcher, this._config);

  final HttpFetcher _fetcher;
  final LlmConfig _config;

  @override
  Future<ArticleAiSelection> select(ArticleAiSelectInput input) async {
    final prompt = buildArticleSelectionPrompt(
      ArticlePromptInput(
        articleText: input.articleText,
        candidates: input.candidates,
        knownSample: input.knownSample,
        totalKnown: input.totalKnown,
        examTargets: input.examTargets,
        difficultyMode: input.difficultyMode,
        extractScope: input.extractScope,
      ),
    );
    final wordsOnly = input.extractScope == ArticleExtractScope.wordsOnly;
    final tokenFloor = wordsOnly
        ? articleAiWordOnlyMaxOutputTokens
        : articleAiMaxOutputTokens;
    try {
      final completion = await LlmClient(_fetcher, _config).complete(
        LlmCallOptions(
          system: prompt.systemPrompt,
          user: prompt.userPrompt,
          schema: wordsOnly
              ? articleAiWordOnlyJsonSchema
              : articleAiSelectionJsonSchema,
          maxOutputTokens: math.max(_config.ai.maxOutputTokens, tokenFloor),
          temperature: _config.ai.temperature,
          thinkingEnabled: _config.ai.thinkingEnabled,
          thinkingBudgetTokens: _config.ai.thinkingBudgetTokens,
          reasoningEffort: _config.ai.reasoningEffort,
        ),
      );
      return _interpret(completion.text);
    } on AppError catch (error) {
      return ArticleAiSelection.failure(
        errorCode: error.code,
        error: error.message,
      );
    }
  }

  /// 把模型输出解析成结构化结果。
  ///
  /// 两步失败的文案分开（与旧版一致）：「不是 JSON」与「结构不符」对用户
  /// 指向不同的排查方向（换模型 / 看模型是否支持 JSON 输出）。
  ArticleAiSelection _interpret(String text) {
    final parsed = extractJsonValue(text);
    if (parsed == null) {
      return const ArticleAiSelection.failure(
        errorCode: AppErrorCode.aiResponseInvalid,
        error: 'AI 返回内容不是有效 JSON，已回退为本地筛选。',
      );
    }
    final normalized = normalizeAiSelectionResponse(parsed);
    if (normalized == null) {
      return const ArticleAiSelection.failure(
        errorCode: AppErrorCode.aiResponseInvalid,
        error: 'AI 返回格式不符合预期，已回退为本地筛选。',
      );
    }
    return normalized;
  }
}
