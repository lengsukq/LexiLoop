/// 爱词霸（金山词霸）provider。
///
/// 对应旧版 `modules/dictionary/providers/iciba.ts`。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/data/dictionary/providers/iciba_parser.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

/// 爱词霸 provider。
class IcibaProvider implements DictionaryProvider {
  /// 以 HTTP 客户端构造。
  const new(this._fetcher);

  final HttpFetcher _fetcher;

  @override
  String get id => 'iciba';

  @override
  Set<String> get providedFields => providerCapabilities['iciba']!;

  @override
  bool isEnabled(AppSettings settings) => settings.providers.icibaEnabled;

  @override
  bool supports(ProviderRequest request) =>
      request.sourceLanguage.toLowerCase().startsWith('en') &&
      request.contentType != LexicalContentType.sentence;

  @override
  Future<ProviderResult?> fetch(ProviderRequest request) async {
    final response = await _get(request.term);
    if (!response.isSuccess) {
      final transient = response.statusCode >= transientServerErrorFloor;
      throw ExternalServiceError(
        transient
            ? AppErrorCode.providerTransientFailure
            : AppErrorCode.requestedFieldsEmpty,
        isTransient: transient,
        details: '金山词霸页面返回 ${response.statusCode}',
      );
    }
    final fields = parseIcibaHtml(
      response.body,
      targetLanguage: request.targetLanguage,
    );
    if (fields == null) return null;
    return ProviderResult(
      fields: fields,
      providerId: id,
      qualityScore: _qualityScore(fields),
    );
  }

  Future<HttpFetchResponse> _get(String term) async {
    try {
      return await _fetcher.get(
        'https://www.iciba.com/word?w=${Uri.encodeComponent(term.trim())}',
        timeout: const Duration(milliseconds: dictionaryProviderTimeoutMs),
        headers: _headers,
      );
    } on HttpFailure catch (error) {
      throw ExternalServiceError(
        AppErrorCode.providerTransientFailure,
        isTransient: true,
        details: error.kind == HttpFailureKind.timeout ? '请求超时' : '网络不可用',
      );
    }
  }
}

/// 请求头。
const Map<String, String> _headers = <String, String>{
  'accept': 'text/html,application/xhtml+xml',
  'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
  'cache-control': 'no-cache',
  'user-agent': 'Mozilla/5.0 LexiLoop',
};

/// 内容饱满度打分（0–100）。
///
/// 爱词霸没有像有道那样的「是否满足请求字段」判断，因此用各字段条数的
/// 加权和近似，权重与有道保持同一量级以便 PRIORITY_FALLBACK 横向比较。
int _qualityScore(Map<String, Object?> fields) {
  var score = 0;
  score += _length(fields, 'definitions') * 6;
  score += _length(fields, 'examples') * 3;
  score += _length(fields, 'phrases') * 2;
  score += _length(fields, 'pronunciations') * 5;
  score += _length(fields, 'forms') * 2;
  score += _length(fields, 'synonyms');
  score += _length(fields, 'confusedWords') * 2;
  final summary = fields['summary'];
  if (summary is Map) {
    final short = summary['shortDefinition'];
    if (short is String && short.trim().isNotEmpty) score += 8;
    if (summary['frequency'] != null) score += 4;
  }
  return score > 100 ? 100 : score;
}

int _length(Map<String, Object?> fields, String field) {
  final value = fields[field];
  return value is List ? value.length : 0;
}
