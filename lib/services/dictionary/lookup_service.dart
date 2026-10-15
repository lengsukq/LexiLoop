/// 词典查询入口：把设置、数据源与管线接起来。
///
/// 旧版把「从设置造 provider」「过滤」「跑管线」散在 `pipeline.ts` 的
/// 三个函数里，`worker.ts` 只能整体调用 `lookupDictionary`。这里把
/// 「造 provider」独立成服务，使 worker 与 UI 复用同一条路径，
/// 测试也可以只替换 HTTP 客户端。
library;

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/data/dictionary/providers/ai_lexical.dart';
import 'package:lexiloop/data/dictionary/providers/dictionary_api.dart';
import 'package:lexiloop/data/dictionary/providers/iciba.dart';
import 'package:lexiloop/data/dictionary/providers/merriam_webster.dart';
import 'package:lexiloop/data/dictionary/providers/my_memory.dart';
import 'package:lexiloop/data/dictionary/providers/youdao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/dictionary/pipeline.dart';
import 'package:lexiloop/services/dictionary/selection.dart';
import 'package:lexiloop/services/llm/llm_client.dart';
import 'package:lexiloop/services/llm/llm_config.dart';

/// 词典查询服务。
class DictionaryLookupService {
  /// 以 HTTP 客户端构造（全部网络调用经由它）。
  const new(this._fetcher);

  final HttpFetcher _fetcher;

  /// 按设置执行一次查询。
  Future<DictionaryLookupResult> lookup({
    required AppSettings settings,
    required ProviderRequest request,
    List<String> selectedProviders = const <String>[],
    ProviderStrategy strategy = ProviderStrategy.priorityFallback,
  }) {
    final providers = selectProviders(
      settings: settings,
      request: request,
      candidates: buildProviders(settings),
      selectedProviders: selectedProviders,
    );
    if (providers.isEmpty) {
      throw const ExternalServiceError(
        AppErrorCode.providerNotFound,
        details: '没有可用的数据源（未启用、不支持该请求，或请求字段无交集）',
      );
    }
    return ProviderPipeline(
      providers: providers,
      strategy: strategy,
    ).lookup(request);
  }

  /// 按设置构造全部数据源（含未启用的，由 selection 过滤）。
  List<DictionaryProvider> buildProviders(AppSettings settings) {
    final llmConfig = llmConfigFromRaw(settings.raw[llmConfigSettingsKey]);
    return <DictionaryProvider>[
      YoudaoProvider(_fetcher),
      IcibaProvider(_fetcher),
      MerriamWebsterProvider(settings, _fetcher),
      DictionaryApiProvider(_fetcher),
      MyMemoryProvider(_fetcher),
      AiLexicalProvider(LlmClient(_fetcher, llmConfig), llmConfig),
    ];
  }
}
