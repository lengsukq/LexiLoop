/// 数据源调用管线。
///
/// 对应旧版 `modules/dictionary/pipeline.ts` 的 `lookupDictionary`。
///
/// **两种策略**：
/// - [ProviderStrategy.parallelMerge]：并发调用全部来源再合并，覆盖最全，
///   代价是每次都打满所有来源（含限流风险）。
/// - [ProviderStrategy.priorityFallback]：按顺序调用，内容既满足请求字段
///   又达到 `providerFallbackQualityThreshold` 就提前终止，省流量。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/dictionary/merge.dart';
import 'package:lexiloop/services/dictionary/selection.dart';

/// 一次管线调用的结果。
class DictionaryLookupResult {
  /// 以各字段构造。
  const new({
    required this.content,
    required this.attempts,
    required this.hasTransientFailure,
    required this.contentSource,
  });

  /// 合并后的内容。
  final DictionaryContent content;

  /// 各数据源的调用记录。
  final List<ProviderAttemptRecord> attempts;

  /// 是否出现过瞬时失败（决定任务是否退避重排）。
  final bool hasTransientFailure;

  /// 内容来源构成。
  final ContentSource contentSource;
}

/// 单个数据源的落定结果。
class _SettledProvider {
  const new({
    required this.content,
    required this.attempt,
    required this.transient,
  });

  final DictionaryContent? content;
  final ProviderAttemptRecord attempt;
  final bool transient;
}

/// 数据源调用管线。
class ProviderPipeline {
  /// 以数据源列表、策略与质量阈值构造。
  const new({
    required this.providers,
    required this.strategy,
    this.qualityThreshold = providerFallbackQualityThreshold,
  });

  /// 本次参与调用的数据源（已按顺序排好）。
  final List<DictionaryProvider> providers;

  /// 调用策略。
  final ProviderStrategy strategy;

  /// `PRIORITY_FALLBACK` 提前终止所需的质量分。
  final double qualityThreshold;

  /// 执行一次查询。
  Future<DictionaryLookupResult> lookup(ProviderRequest request) async {
    final settled = await _settle(request);
    final content = mergeDictionaryContent(<DictionaryContent?>[
      for (final item in settled) item.content,
    ]);
    return DictionaryLookupResult(
      content: content,
      attempts: <ProviderAttemptRecord>[
        for (final item in settled) item.attempt,
      ],
      hasTransientFailure: settled.any((item) => item.transient),
      contentSource: _contentSource(settled),
    );
  }

  Future<List<_SettledProvider>> _settle(ProviderRequest request) {
    if (strategy == ProviderStrategy.parallelMerge) {
      return Future.wait(<Future<_SettledProvider>>[
        for (final provider in providers) _runProvider(provider, request),
      ]);
    }
    return _settleByPriority(request);
  }

  /// 按顺序调用，达标即停。
  Future<List<_SettledProvider>> _settleByPriority(
    ProviderRequest request,
  ) async {
    final settled = <_SettledProvider>[];
    var accumulated = emptyDictionaryContent();
    for (final provider in providers) {
      final result = await _runProvider(provider, request);
      settled.add(result);
      final content = result.content;
      if (content != null) {
        accumulated = mergeDictionaryContent(<DictionaryContent>[
          accumulated,
          content,
        ]);
      }
      if (_requestedContentReady(accumulated, request) &&
          fallbackQualityScore(accumulated, request) >= qualityThreshold) {
        break;
      }
    }
    return settled;
  }

  Future<_SettledProvider> _runProvider(
    DictionaryProvider provider,
    ProviderRequest request,
  ) async {
    final stopwatch = Stopwatch()..start();
    final wanted = request.wantedFields.toList(growable: false);
    try {
      final result = await provider.fetch(request);
      stopwatch.stop();
      if (result == null) {
        return _SettledProvider(
          content: null,
          transient: false,
          attempt: ProviderAttemptRecord(
            providerId: provider.id,
            status: ProviderAttemptStatus.empty,
            durationMs: stopwatch.elapsedMilliseconds,
            fieldsReturned: const <String>[],
            errorCode: AppErrorCode.requestedFieldsEmpty.code,
            errorMessage: '数据源没有返回可用内容',
          ),
        );
      }
      final projected = projectDictionaryContent(
        DictionaryContent(result.fields),
        wanted,
      );
      final returned = fieldsReturned(projected, wanted);
      final hasContent =
          returned.isNotEmpty || (wanted.isEmpty && result.fields.isNotEmpty);
      return _SettledProvider(
        content: hasContent ? projected : null,
        transient: false,
        attempt: ProviderAttemptRecord(
          providerId: provider.id,
          status: hasContent
              ? ProviderAttemptStatus.success
              : ProviderAttemptStatus.empty,
          durationMs: stopwatch.elapsedMilliseconds,
          fieldsReturned: returned,
          metadata: result.metadata,
        ),
      );
    } on ExternalServiceError catch (error) {
      stopwatch.stop();
      return _SettledProvider(
        content: null,
        transient: error.isTransient,
        attempt: ProviderAttemptRecord(
          providerId: provider.id,
          status: ProviderAttemptStatus.failed,
          durationMs: stopwatch.elapsedMilliseconds,
          fieldsReturned: const <String>[],
          errorCode: error.code.code,
          errorMessage: error.details == null
              ? error.message
              : '${error.message}（${error.details}）',
        ),
      );
    }
  }

  ContentSource _contentSource(List<_SettledProvider> settled) {
    var aiSuccess = false;
    var nonAiSuccess = false;
    for (final item in settled) {
      if (item.attempt.status != ProviderAttemptStatus.success) continue;
      if (isAiProviderId(item.attempt.providerId)) {
        aiSuccess = true;
      } else {
        nonAiSuccess = true;
      }
    }
    if (aiSuccess && !nonAiSuccess) return ContentSource.aiOnly;
    if (aiSuccess) return ContentSource.mixed;
    return ContentSource.dictionaryOnly;
  }

  bool _requestedContentReady(
    DictionaryContent content,
    ProviderRequest request,
  ) =>
      requestedFieldStatusForLanguages(
        content,
        request.wantedFields.toList(growable: false),
        request.sourceLanguage,
        request.targetLanguage,
      ) ==
      InitializationStatus.ready;
}

/// `PRIORITY_FALLBACK` 的质量分（0–1）。
///
/// 三项加权：目标语言释义 0.5、例句 0.3、音标 0.2。
/// 句子类词条缺少译文时封顶，避免「字段齐全但无法判题」被当成高质量。
double fallbackQualityScore(
  DictionaryContent content,
  ProviderRequest request,
) {
  final definitions = content.records(definitionsField);
  final hasTarget = definitions.any(
    (item) =>
        item['language'] == request.targetLanguage && _nonEmpty(item['text']),
  );
  final hasAny = definitions.any((item) => _nonEmpty(item['text']));
  final targetFactor = hasTarget
      ? fallbackQualityFullFactor
      : hasAny
      ? fallbackQualityPartialFactor
      : 0;
  final exampleFactor = _exampleFactor(content.records('examples').length);
  final phoneticFactor =
      content
          .records('pronunciations')
          .any((item) => _nonEmpty(item['phonetic']))
      ? fallbackQualityFullFactor
      : 0;
  var score =
      targetFactor * fallbackQualityTargetDefinitionWeight +
      exampleFactor * fallbackQualityExamplesWeight +
      phoneticFactor * fallbackQualityPhoneticsWeight;
  if (request.contentType == LexicalContentType.sentence) {
    final summary = content.record(summaryField);
    if (!_nonEmpty(summary['translation']) &&
        score > fallbackQualitySentenceTranslationCap) {
      score = fallbackQualitySentenceTranslationCap;
    }
  }
  return score;
}

double _exampleFactor(int count) {
  if (count >= fallbackQualityExamplesFullCount) {
    return fallbackQualityFullFactor;
  }
  if (count >= fallbackQualityExamplesPartialCount) {
    return fallbackQualityPartialFactor;
  }
  return 0;
}

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;
